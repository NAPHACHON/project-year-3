<?php
namespace Tests\Feature;

use App\Models\{User, Package, GamingStation, SessionLog};
use App\Services\{CafeService, TokenService};
use Illuminate\Foundation\Testing\TestCase;
use Illuminate\Support\Facades\{Artisan, DB};
use Illuminate\Support\Carbon;

class BookingTest extends TestCase {
    private User $member;
    private User $other;
    private User $admin;
    private GamingStation $station;
    private CafeService $service;

    protected function setUp(): void {
        parent::setUp();
        if (config('database.default') !== 'sqlite' || config('database.connections.sqlite.database') !== ':memory:') {
            throw new \RuntimeException('Tests require an isolated in-memory SQLite database.');
        }
        Artisan::call('migrate:fresh', ['--force' => true]);
        Carbon::setTestNow(Carbon::parse('2026-10-05 12:00:00', 'Asia/Bangkok'));
        $this->member = User::create(['name'=>'Member','email'=>'m@test.local','phone'=>'001','password'=>'test-password','role'=>'user']);
        $this->other = User::create(['name'=>'Other','email'=>'o@test.local','phone'=>'002','password'=>'test-password','role'=>'user']);
        $this->admin = User::create(['name'=>'Admin','email'=>'a@test.local','phone'=>'003','password'=>'test-password','role'=>'admin']);
        $package = Package::create(['name'=>'Normal','hourly_rate'=>'20.00']);
        $this->station = GamingStation::create(['station_code'=>'PC-01','zone_name'=>'Normal','package_id'=>$package->id,'status'=>'available']);
        $this->service = app(CafeService::class);
    }
    protected function tearDown(): void {Carbon::setTestNow(); parent::tearDown();}
    private function headers(User $user): array {return ['Authorization'=>'Bearer '.app(TokenService::class)->issue($user)];}
    private function postAs(User $user, string $path, array $body=[]){return $this->postJson('/api/v1'.$path, $body, $this->headers($user));}
    private function active(int $hours=2): SessionLog {
        $s=$this->service->reserve($this->member,$this->station->id,$hours);
        return $this->service->start($s->id,true);
    }
    private function advance(int $minutes,int $seconds=0): void {Carbon::setTestNow(now()->addMinutes($minutes)->addSeconds($seconds));}

    public function test_member_booking_stores_hours_and_server_price(): void {
        $this->postAs($this->member,'/bookings',['station_id'=>$this->station->id,'hours'=>2,'quoted_amount'=>0])
            ->assertCreated()->assertJsonPath('data.planned_minutes',120)->assertJsonPath('data.quoted_amount','40.00')->assertJsonPath('data.prepaid_amount','0.00');
        $this->assertSame('reserved',$this->station->fresh()->status);
    }
    public function test_duration_is_required_and_bounded_to_integer_hours(): void {
        foreach ([null,0,25,1.5,'invalid'] as $hours) {
            $body=['station_id'=>$this->station->id];if($hours!==null)$body['hours']=$hours;
            $this->postAs($this->member,'/bookings',$body)->assertUnprocessable()->assertJsonValidationErrors('hours');
        }
        $this->assertSame(0,SessionLog::count());
        $this->postAs($this->member,'/bookings',['station_id'=>$this->station->id,'hours'=>24])->assertCreated()->assertJsonPath('data.planned_minutes',1440);
    }
    public function test_admin_can_book_duration_for_member(): void {
        $this->postAs($this->admin,'/admin/bookings',['station_id'=>$this->station->id,'user_id'=>$this->member->id,'hours'=>3])
            ->assertCreated()->assertJsonPath('data.quoted_amount','60.00');
        $this->postAs($this->member,'/admin/bookings',['station_id'=>$this->station->id,'user_id'=>$this->member->id,'hours'=>1])->assertForbidden();
    }
    public function test_start_requires_counter_receipt_and_freezes_price(): void {
        $s=$this->service->reserve($this->member,$this->station->id,2);
        $this->station->package->update(['hourly_rate'=>'99.00']);
        $this->postAs($this->admin,"/admin/sessions/{$s->id}/start")->assertUnprocessable();
        $this->assertSame('reserved',$s->fresh()->status);
        $this->postAs($this->member,"/admin/sessions/{$s->id}/start",['payment_received'=>true])->assertForbidden();
        $this->postAs($this->admin,"/admin/sessions/{$s->id}/start",['payment_received'=>true])->assertOk()->assertJsonPath('data.prepaid_amount','40.00');
        $this->assertSame('2026-10-05 14:00:00',$s->fresh()->scheduled_end_at->format('Y-m-d H:i:s'));
    }
    public function test_reserved_cancellation_is_free_and_retry_is_safe(): void {
        $s=$this->service->reserve($this->member,$this->station->id,2);
        $this->postAs($this->member,"/sessions/{$s->id}/cancel")->assertOk()->assertJsonPath('data.status','cancelled')->assertJsonPath('data.refund_amount','0.00');
        $this->postAs($this->member,"/sessions/{$s->id}/cancel")->assertOk();
        $this->assertSame('available',$this->station->fresh()->status);
    }
    public function test_member_ends_early_and_refund_is_pending(): void {
        $s=$this->active();$this->advance(60);
        $this->getJson("/api/v1/sessions/{$s->id}/settlement?use_reward=0",$this->headers($this->member))->assertOk()->assertJsonPath('data.refund_amount','20.00');
        $this->assertSame('active',$s->fresh()->status);
        $this->postAs($this->member,"/sessions/{$s->id}/end",['use_reward'=>false])->assertOk()->assertJsonPath('data.total_amount','20.00')->assertJsonPath('data.refund_amount','20.00')->assertJsonPath('data.refund_status','pending');
        $this->assertSame('available',$this->station->fresh()->status);
    }
    public function test_active_cancel_also_settles(): void {
        $s=$this->active();$this->advance(30);
        $this->postAs($this->member,"/sessions/{$s->id}/cancel")->assertOk()->assertJsonPath('data.status','completed')->assertJsonPath('data.refund_amount','30.00');
    }
    public function test_second_end_does_not_change_bill_or_new_station_booking(): void {
        $s=$this->active();$this->advance(30);$this->service->finish($this->member,$s->id,false);
        $this->service->reserve($this->other,$this->station->id,1);$this->advance(5);
        $this->postAs($this->member,"/sessions/{$s->id}/end",['use_reward'=>true])->assertOk()->assertJsonPath('data.refund_amount','30.00')->assertJsonPath('data.minutes_used',30);
        $this->assertSame('reserved',$this->station->fresh()->status);
    }
    public function test_only_owner_or_admin_can_preview_cancel_or_end(): void {
        $s=$this->active();
        $this->getJson("/api/v1/sessions/{$s->id}/settlement",$this->headers($this->other))->assertForbidden();
        $this->postAs($this->other,"/sessions/{$s->id}/end")->assertForbidden();
        $this->postAs($this->other,"/sessions/{$s->id}/cancel")->assertForbidden();
        $this->assertSame('active',$s->fresh()->status);
        $this->advance(60);
        $this->postAs($this->admin,"/admin/sessions/{$s->id}/finish",['use_reward'=>false])->assertOk()->assertJsonPath('data.refund_amount','20.00');
    }
    public function test_refund_confirmation_is_admin_only_and_idempotent(): void {
        $s=$this->active();$this->advance(60);$this->service->finish($this->member,$s->id,false);
        $this->postAs($this->member,"/admin/sessions/{$s->id}/refund")->assertForbidden();
        $this->postAs($this->admin,"/admin/sessions/{$s->id}/refund")->assertOk()->assertJsonPath('data.refund_status','paid')->assertJsonPath('data.refunded_by',$this->admin->id);
        $time=$s->fresh()->refunded_at;$this->advance(5);
        $this->postAs($this->admin,"/admin/sessions/{$s->id}/refund")->assertOk();
        $this->assertEquals($time,$s->fresh()->refunded_at);
    }
    public function test_completed_refund_is_visible_only_to_owner_and_admin(): void {
        $s=$this->active();$this->advance(60);$this->service->finish($this->member,$s->id,false);
        $this->getJson('/api/v1/data',$this->headers($this->member))->assertOk()->assertJsonCount(1,'refunds');
        $this->getJson('/api/v1/data',$this->headers($this->other))->assertOk()->assertJsonCount(0,'refunds')->assertJsonCount(0,'history');
        $this->getJson('/api/v1/data',$this->headers($this->admin))->assertOk()->assertJsonCount(1,'refunds');
    }
    public function test_elapsed_minute_rounding_and_overtime_balance(): void {
        $s=$this->active(1);$this->advance(60,1);
        $this->postAs($this->member,"/sessions/{$s->id}/end")->assertOk()->assertJsonPath('data.minutes_used',61)->assertJsonPath('data.total_amount','20.33')->assertJsonPath('data.refund_amount','0.00')->assertJsonPath('data.balance_due','0.33');
    }
    public function test_zero_time_returns_full_prepaid_and_exact_plan_has_no_refund(): void {
        $s=$this->active();$s=$this->service->finish($this->member,$s->id,false);$this->assertSame('40.00',$s->refund_amount);
        $s=$this->active(1);$this->advance(60);
        $this->postAs($this->member,"/sessions/{$s->id}/end")->assertOk()->assertJsonPath('data.refund_status','none')->assertJsonPath('data.total_amount','20.00');
        $this->postAs($this->admin,"/admin/sessions/{$s->id}/refund")->assertUnprocessable();
    }
    public function test_reward_preview_does_not_consume_reward_and_end_consumes_once(): void {
        SessionLog::create(['session_code'=>'OLD-PAID','user_id'=>$this->member->id,'station_id'=>$this->station->id,'status'=>'completed','reserved_at'=>now()->subDay(),'started_at'=>now()->subDay(),'ended_at'=>now()->subDay()->addMinutes(600),'hourly_rate'=>'20.00','minutes_used'=>600,'total_amount'=>'200.00']);
        $s=$this->active(2);$this->advance(30);
        $this->getJson("/api/v1/sessions/{$s->id}/settlement?use_reward=1",$this->headers($this->member))->assertOk()->assertJsonPath('data.free_minutes_used',30)->assertJsonPath('data.refund_amount','40.00');
        $this->assertSame(60,$this->service->rewards($this->member->id)['free_minutes_available']);
        $this->postAs($this->member,"/sessions/{$s->id}/end",['use_reward'=>true])->assertOk()->assertJsonPath('data.free_minutes_used',30)->assertJsonPath('data.total_amount','0.00');
        $this->assertSame(30,$this->service->rewards($this->member->id)['free_minutes_available']);
        $this->postAs($this->member,"/sessions/{$s->id}/end",['use_reward'=>true])->assertOk();
        $this->assertSame(30,$this->service->rewards($this->member->id)['free_minutes_available']);
    }
    public function test_legacy_booking_keeps_pay_after_playing(): void {
        $s=SessionLog::create(['session_code'=>'LEGACY','user_id'=>$this->member->id,'station_id'=>$this->station->id,'status'=>'reserved','reserved_at'=>now(),'hourly_rate'=>'20.00']);
        $this->station->update(['status'=>'reserved']);$this->service->start($s->id);$this->advance(30);
        $this->postAs($this->member,"/sessions/{$s->id}/end")->assertOk()->assertJsonPath('data.planned_minutes',null)->assertJsonPath('data.refund_amount','0.00')->assertJsonPath('data.balance_due','10.00');
    }
    public function test_expired_booking_cannot_start_and_is_released(): void {
        $s=$this->service->reserve($this->member,$this->station->id,1);$this->advance(15);
        $this->postAs($this->admin,"/admin/sessions/{$s->id}/start",['payment_received'=>true])->assertUnprocessable();
        $this->assertSame('expired',$s->fresh()->status);$this->assertSame('available',$this->station->fresh()->status);
    }
    public function test_one_open_booking_per_member_and_station(): void {
        $this->service->reserve($this->member,$this->station->id,1);
        $this->postAs($this->other,'/bookings',['station_id'=>$this->station->id,'hours'=>1])->assertUnprocessable();
        $second=GamingStation::create(['station_code'=>'PC-02','zone_name'=>'Normal','package_id'=>$this->station->package_id,'status'=>'available']);
        $this->postAs($this->member,'/bookings',['station_id'=>$second->id,'hours'=>1])->assertUnprocessable();
        $this->assertSame('available',$second->fresh()->status);
    }
    public function test_web_and_member_views_render_and_share_booking_endpoints(): void {
        $this->actingAs($this->member)->get('/dashboard')->assertOk()->assertSee('booking-hours')->assertSee('settlement-modal');
        $this->get('/flutter')->assertOk()->assertSee('/js/cafe.js')->assertSee('refunds');
        $this->postJson('/web-api/bookings',['station_id'=>$this->station->id,'hours'=>2])->assertCreated();
        $s=SessionLog::first();$this->service->start($s->id,true);$this->advance(60);
        $this->getJson("/web-api/sessions/{$s->id}/settlement")->assertOk()->assertJsonPath('data.refund_amount','20.00');
        $this->postJson("/web-api/sessions/{$s->id}/end")->assertOk()->assertJsonPath('data.refund_status','pending');
    }
    public function test_upgrade_migration_preserves_existing_history(): void {
        $migration=require database_path('migrations/2026_10_05_000001_add_booking_time_and_refunds.php');
        $migration->down();
        DB::table('session_logs')->insert(['session_code'=>'BEFORE-UPGRADE','user_id'=>$this->member->id,'station_id'=>$this->station->id,'status'=>'completed','reserved_at'=>now(),'minutes_used'=>30,'total_amount'=>'10.00','hourly_rate'=>'20.00']);
        $migration->up();
        $old=SessionLog::where('session_code','BEFORE-UPGRADE')->firstOrFail();
        $this->assertSame('10.00',$old->total_amount);$this->assertNull($old->planned_minutes);$this->assertSame('0.00',$old->prepaid_amount);$this->assertSame(3,User::count());
    }
}
