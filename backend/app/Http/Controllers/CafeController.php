<?php
namespace App\Http\Controllers;
use App\Models\{User,Package,GamingStation,SessionLog};
use App\Services\CafeService;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
class CafeController extends Controller {
 public function data(Request $r,CafeService $service){
  $service->expireReservations();$user=$r->user();$admin=$user->role==='admin';
  $stations=GamingStation::with('package')->orderBy('station_code')->get();
  $query=SessionLog::with(['station.package','user:id,name']);
  if(!$admin)$query->where('user_id',$user->id);
  $open=(clone $query)->whereIn('status',['reserved','active'])->orderBy('id')->get();
  $history=(clone $query)->whereNotIn('status',['reserved','active'])->orderByDesc('id')->limit(100)->get();
  $refunds=(clone $query)->where('refund_status','pending')->orderBy('ended_at')->limit(100)->get();
  $stats=null;$popular=[];
  if($admin){
   $stats=['revenue_today'=>(float)SessionLog::where('status','completed')->whereDate('ended_at',today())->sum('total_amount'),'completed_today'=>SessionLog::where('status','completed')->whereDate('ended_at',today())->count(),'available'=>$stations->where('status','available')->count(),'in_use'=>$stations->where('status','in_use')->count()];
   $popular=GamingStation::withSum(['sessions as total_minutes'=>fn($q)=>$q->where('status','completed')],'minutes_used')->orderByDesc('total_minutes')->limit(5)->get(['id','station_code','zone_name']);
  }
  return response()->json(['user'=>$user,'server_time'=>now()->toIso8601String(),'stations'=>$stations,'packages'=>Package::all(),'open_sessions'=>$open,'history'=>$history,'refunds'=>$refunds,'rewards'=>$service->rewards($user->id),'stats'=>$stats,'popular'=>$popular,'members'=>$admin?User::where('role','user')->get(['id','name','email']):[]]);
 }
 public function book(Request $r,CafeService $s){
  $d=$r->validate(['station_id'=>'required|integer|exists:gaming_stations,id','hours'=>'required|integer|between:1,24']);
  abort_unless($r->user()->role==='user',403);
  return response()->json(['data'=>$s->reserve($r->user(),$d['station_id'],$d['hours']),'message'=>'จองแล้ว กรุณาชำระเงินและติดต่อเคาน์เตอร์ภายใน 15 นาที'],201);
 }
 public function cancel(Request $r,int $id,CafeService $s){
  $r->validate(['use_reward'=>'sometimes|boolean']);
  return $this->sessionResult($s->cancel($r->user(),$id,$r->boolean('use_reward')),'ยกเลิกการจองแล้ว ไม่มีค่าบริการ');
 }
 public function reserveForMember(Request $r,CafeService $s){
  $d=$r->validate(['user_id'=>['required','integer',Rule::exists('users','id')->where('role','user')],'station_id'=>'required|integer|exists:gaming_stations,id','hours'=>'required|integer|between:1,24']);
  return response()->json(['data'=>$s->reserve(User::findOrFail($d['user_id']),$d['station_id'],$d['hours']),'message'=>'บันทึกการจองให้สมาชิกแล้ว กรุณารับเงินก่อนเริ่มเล่น'],201);
 }
 public function start(Request $r,int $id,CafeService $s){
  $r->validate(['payment_received'=>'sometimes|boolean']);
  $session=$s->start($id,$r->boolean('payment_received'));
  return response()->json(['data'=>$session,'message'=>$session->paid_at?'รับเงินและเริ่มนับเวลาแล้ว':'เริ่มนับเวลาแล้ว รายการเดิมคิดค่าบริการหลังเล่น']);
 }
 public function preview(Request $r,int $id,CafeService $s){
  $r->validate(['use_reward'=>'sometimes|in:0,1']);
  return response()->json(['data'=>$s->preview($r->user(),$id,$r->boolean('use_reward'))]);
 }
 public function end(Request $r,int $id,CafeService $s){
  $r->validate(['use_reward'=>'sometimes|boolean']);
  return $this->sessionResult($s->finish($r->user(),$id,$r->boolean('use_reward')));
 }
 public function finish(Request $r,int $id,CafeService $s){
  $r->validate(['use_reward'=>'required|boolean']);
  return $this->sessionResult($s->finish($r->user(),$id,$r->boolean('use_reward')));
 }
 public function refund(Request $r,int $id,CafeService $s){
  return response()->json(['data'=>$s->confirmRefund($r->user(),$id),'message'=>'บันทึกว่าเคาน์เตอร์คืนเงินส่วนต่างแล้ว']);
 }
 private function sessionResult(SessionLog $session,string $message='จบการใช้งานแล้ว'){
  if($session->status==='completed'){
   $message='จบการใช้งานแล้ว ค่าบริการจริง '.$session->total_amount.' บาท';
   if($session->refund_status==='pending')$message.=' กรุณาติดต่อเคาน์เตอร์เพื่อรับเงินส่วนต่าง '.$session->refund_amount.' บาท';
   elseif((float)$session->balance_due>0)$message.=' กรุณาชำระเพิ่มที่เคาน์เตอร์ '.$session->balance_due.' บาท';
  }
  return response()->json(['data'=>$session,'message'=>$message]);
 }
 public function status(Request $r,int $id,CafeService $s){$d=$r->validate(['status'=>'required|in:available,maintenance']);return response()->json(['data'=>$s->setStationStatus($id,$d['status']),'message'=>'เปลี่ยนสถานะเครื่องแล้ว']);}
 public function package(Request $r,?int $id=null){$d=$r->validate(['name'=>'required|string|max:100','hourly_rate'=>'required|numeric|between:0.01,99999']);$p=$id?Package::findOrFail($id):new Package;$p->fill($d)->save();return response()->json(['data'=>$p,'message'=>'บันทึกแพ็กเกจแล้ว']);}
 public function station(Request $r,?int $id=null){
  $d=$r->validate(['station_code'=>['required','regex:/^[A-Za-z0-9_-]{1,30}$/',Rule::unique('gaming_stations')->ignore($id)],'zone_name'=>'required|string|max:100','package_id'=>'required|integer|exists:packages,id','specs_info'=>'nullable|string|max:255']);
  $station=$id?GamingStation::findOrFail($id):new GamingStation;
  $station->fill($d);if(!$id)$station->status='available';$station->save();
  return response()->json(['data'=>$station,'message'=>'บันทึกข้อมูลเครื่องแล้ว']);
 }
}
