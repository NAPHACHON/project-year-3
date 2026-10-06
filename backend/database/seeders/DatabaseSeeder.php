<?php
namespace Database\Seeders;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;
use App\Models\{User,Package,GamingStation};
class DatabaseSeeder extends Seeder {
 public function run():void {
  // Demo accounts only; repeated seeding never replaces passwords or real records.
  User::firstOrCreate(['email'=>'admin@cybercafe.test'],['name'=>'ผู้ดูแลตัวอย่าง','phone'=>'0000000001','password'=>Hash::make('AdminCafe!2026'),'role'=>'admin']);
  User::firstOrCreate(['email'=>'member@cybercafe.test'],['name'=>'สมาชิกตัวอย่าง','phone'=>'0000000002','password'=>Hash::make('MemberCafe!2026'),'role'=>'user']);
  $packages=[];
  foreach([['ทั่วไป',20],['VIP',35],['สตรีมเมอร์',50]] as [$name,$rate])$packages[]=Package::firstOrCreate(['name'=>$name],['hourly_rate'=>$rate]);
  foreach(range(1,10) as $i){$p=$packages[$i<=6?0:($i<=9?1:2)];GamingStation::firstOrCreate(['station_code'=>sprintf('PC-%02d',$i)],['package_id'=>$p->id,'zone_name'=>$p->name,'status'=>$i===10?'maintenance':'available','specs_info'=>$i<=6?'Core i5 / RAM 16 GB / จอ 144 Hz':'Core i7 / RAM 32 GB / จอ 240 Hz']);}
 }
}
