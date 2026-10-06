<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
use App\Services\Billing;

class SessionLog extends Model {
    public $timestamps = false;
    protected $guarded = ['id'];
    protected $appends = ['balance_due'];

    protected function casts(): array {
        return ['user_id' => 'integer', 'station_id' => 'integer',
            'reserved_at' => 'datetime', 'started_at' => 'datetime', 'ended_at' => 'datetime',
            'paid_at' => 'datetime', 'scheduled_end_at' => 'datetime', 'refunded_at' => 'datetime',
            'hourly_rate' => 'decimal:2', 'total_amount' => 'decimal:2',
            'quoted_amount' => 'decimal:2', 'prepaid_amount' => 'decimal:2',
            'refund_amount' => 'decimal:2', 'planned_minutes' => 'integer',
            'minutes_used' => 'integer', 'free_minutes_used' => 'integer'];
    }

    public function getBalanceDueAttribute(): string {
        return Billing::money(max(0, Billing::cents((string) $this->total_amount)
            - Billing::cents((string) $this->prepaid_amount)));
    }

    public function user() { return $this->belongsTo(User::class); }
    public function station() { return $this->belongsTo(GamingStation::class, 'station_id'); }
}
