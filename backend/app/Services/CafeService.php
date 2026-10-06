<?php
namespace App\Services;

use App\Models\{User, GamingStation, SessionLog};
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class CafeService {
    private function fail(string $message): never {
        throw ValidationException::withMessages(['operation' => $message]);
    }

    private function authorizeOwner(User $actor, SessionLog $session): void {
        abort_unless($actor->role === 'admin' || $session->user_id === $actor->id,
            403, 'จัดการได้เฉพาะรายการของตนเอง');
    }

    public function expireReservations(): int {
        $ids = SessionLog::where('status', 'reserved')
            ->where('reserved_at', '<=', now()->subMinutes(15))->pluck('id');
        $count = 0;
        foreach ($ids as $id) {
            $count += DB::transaction(function () use ($id) {
                $candidate = SessionLog::find($id);
                if (!$candidate) return 0;
                $station = GamingStation::lockForUpdate()->findOrFail($candidate->station_id);
                $session = SessionLog::lockForUpdate()->findOrFail($id);
                if ($session->status !== 'reserved'
                    || $session->reserved_at->gt(now()->subMinutes(15))) return 0;
                $session->update(['status' => 'expired', 'ended_at' => now()]);
                if ($station->status === 'reserved') $station->update(['status' => 'available']);
                return 1;
            }, 3);
        }
        return $count;
    }

    public function rewards(int $userId): array {
        $rows = SessionLog::where('user_id', $userId)->where('status', 'completed')
            ->get(['minutes_used', 'free_minutes_used']);
        $paid = max(0, (int) $rows->sum('minutes_used') - (int) $rows->sum('free_minutes_used'));
        $used = (int) $rows->sum('free_minutes_used');
        return ['paid_minutes' => $paid,
            'free_minutes_available' => Billing::availableFreeMinutes($paid, $used),
            'free_minutes_used' => $used, 'minutes_to_next_reward' => 600 - ($paid % 600)];
    }

    public function reserve(User $user, int $stationId, int $hours): SessionLog {
        if ($hours < 1 || $hours > 24) $this->fail('เลือกเวลาเล่นตั้งแต่ 1 ถึง 24 ชั่วโมง');
        $this->expireReservations();
        return DB::transaction(function () use ($user, $stationId, $hours) {
            User::lockForUpdate()->findOrFail($user->id);
            $station = GamingStation::with('package')->lockForUpdate()->findOrFail($stationId);
            if ($station->status !== 'available') $this->fail('เครื่องนี้ไม่ว่าง กรุณาเลือกเครื่องอื่น');
            if (SessionLog::where('user_id', $user->id)->whereIn('status', ['reserved', 'active'])->exists()) {
                $this->fail('คุณมีการจองหรือกำลังใช้เครื่องอยู่แล้ว');
            }
            $minutes = $hours * 60;
            $rate = (string) $station->package->hourly_rate;
            $session = SessionLog::create(['session_code' => 'SES-' . Str::ulid(),
                'user_id' => $user->id, 'station_id' => $station->id, 'status' => 'reserved',
                'reserved_at' => now(), 'hourly_rate' => $rate, 'planned_minutes' => $minutes,
                'quoted_amount' => Billing::amount($minutes, 0, $rate), 'prepaid_amount' => '0.00']);
            $station->update(['status' => 'reserved']);
            return $session;
        }, 3);
    }

    public function cancel(User $actor, int $id, bool $useReward = false): SessionLog {
        $this->expireReservations();
        return DB::transaction(function () use ($actor, $id, $useReward) {
            $candidate = SessionLog::findOrFail($id);
            $this->authorizeOwner($actor, $candidate);
            User::lockForUpdate()->findOrFail($candidate->user_id);
            $station = GamingStation::lockForUpdate()->findOrFail($candidate->station_id);
            $session = SessionLog::lockForUpdate()->findOrFail($id);
            if (in_array($session->status, ['cancelled', 'completed'], true)) return $session;
            if ($session->status === 'active') return $this->close($session, $station, $useReward);
            if ($session->status !== 'reserved') $this->fail('รายการนี้ยกเลิกไม่ได้แล้ว');
            // Reservations have not been paid; no refund is created before start.
            $session->update(['status' => 'cancelled', 'ended_at' => now()]);
            $station->update(['status' => 'available']);
            return $session;
        }, 3);
    }

    public function start(int $id, bool $paymentReceived = false): SessionLog {
        $this->expireReservations();
        return DB::transaction(function () use ($id, $paymentReceived) {
            $candidate = SessionLog::findOrFail($id);
            User::lockForUpdate()->findOrFail($candidate->user_id);
            $station = GamingStation::lockForUpdate()->findOrFail($candidate->station_id);
            $session = SessionLog::lockForUpdate()->findOrFail($id);
            if ($session->status === 'active') return $session;
            if ($session->status !== 'reserved' || $station->status !== 'reserved') {
                $this->fail('รายการนี้เริ่มเล่นไม่ได้ หรือการจองหมดเวลาแล้ว');
            }
            $start = now();
            $changes = ['status' => 'active', 'started_at' => $start];
            if ($session->planned_minutes !== null) {
                if (!$paymentReceived) $this->fail('กรุณายืนยันว่าเคาน์เตอร์รับเงินแล้วก่อนเริ่มเล่น');
                $changes += ['prepaid_amount' => $session->quoted_amount, 'paid_at' => $start,
                    'scheduled_end_at' => $start->copy()->addMinutes($session->planned_minutes)];
            }
            $session->update($changes);
            $station->update(['status' => 'in_use']);
            return $session;
        }, 3);
    }

    private function calculate(SessionLog $session, bool $useReward, ?int $endTimestamp = null): array {
        $minutes = Billing::minutes($session->started_at->timestamp, $endTimestamp ?? now()->timestamp);
        $free = $useReward ? min($minutes, $this->rewards($session->user_id)['free_minutes_available']) : 0;
        return Billing::settlement($minutes, $free, (string) $session->hourly_rate,
            (string) $session->prepaid_amount);
    }

    public function preview(User $actor, int $id, bool $useReward = false): array {
        $session = SessionLog::findOrFail($id);
        $this->authorizeOwner($actor, $session);
        if ($session->status === 'completed') {
            return $session->only(['minutes_used', 'free_minutes_used', 'total_amount',
                'prepaid_amount', 'refund_amount', 'refund_status', 'balance_due']);
        }
        if ($session->status !== 'active' || !$session->started_at) $this->fail('คำนวณได้เฉพาะรายการที่กำลังเล่น');
        return $this->calculate($session, $useReward) + ['refund_status' => 'estimate'];
    }

    public function finish(User $actor, int $id, bool $useReward): SessionLog {
        return DB::transaction(function () use ($actor, $id, $useReward) {
            $candidate = SessionLog::findOrFail($id);
            $this->authorizeOwner($actor, $candidate);
            User::lockForUpdate()->findOrFail($candidate->user_id);
            $station = GamingStation::lockForUpdate()->findOrFail($candidate->station_id);
            $session = SessionLog::lockForUpdate()->findOrFail($id);
            if ($session->status === 'completed') return $session;
            return $this->close($session, $station, $useReward);
        }, 3);
    }

    private function close(SessionLog $session, GamingStation $station, bool $useReward): SessionLog {
        if ($session->status !== 'active' || !$session->started_at) $this->fail('จบได้เฉพาะรายการที่เริ่มเล่นแล้ว');
        $end = now();
        $bill = $this->calculate($session, $useReward, $end->timestamp);
        $session->update(['status' => 'completed', 'ended_at' => $end,
            'minutes_used' => $bill['minutes_used'], 'free_minutes_used' => $bill['free_minutes_used'],
            'total_amount' => $bill['total_amount'], 'refund_amount' => $bill['refund_amount'],
            'refund_status' => Billing::cents($bill['refund_amount']) > 0 ? 'pending' : 'none']);
        $station->update(['status' => 'available']);
        return $session;
    }

    public function confirmRefund(User $actor, int $id): SessionLog {
        abort_unless($actor->role === 'admin', 403);
        return DB::transaction(function () use ($actor, $id) {
            $session = SessionLog::lockForUpdate()->findOrFail($id);
            if ($session->refund_status === 'paid') return $session;
            if ($session->status !== 'completed' || $session->refund_status !== 'pending'
                || Billing::cents((string) $session->refund_amount) <= 0) {
                $this->fail('รายการนี้ไม่มีเงินส่วนต่างที่รอคืน');
            }
            // This records a cash refund already handed over by the counter.
            $session->update(['refund_status' => 'paid', 'refunded_at' => now(), 'refunded_by' => $actor->id]);
            return $session;
        }, 3);
    }

    public function setStationStatus(int $id, string $status): GamingStation {
        return DB::transaction(function () use ($id, $status) {
            $station = GamingStation::lockForUpdate()->findOrFail($id);
            if (SessionLog::where('station_id', $id)->whereIn('status', ['reserved', 'active'])->exists()) {
                $this->fail('เครื่องนี้มีรายการใช้งานอยู่ ต้องปิดหรือยกเลิกก่อน');
            }
            $station->update(['status' => $status]);
            return $station;
        }, 3);
    }
}
