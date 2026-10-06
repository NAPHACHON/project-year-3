<?php
namespace App\Http\Controllers;
use App\Models\User;
use App\Services\TokenService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{Auth,Hash};
use Illuminate\Validation\ValidationException;
class AuthController extends Controller {
 public function login(Request $r,TokenService $tokens){
  $d=$r->validate(['email'=>'required|email','password'=>'required|string']);
  $user=User::where('email',$d['email'])->first();
  if(!$user||!Hash::check($d['password'],$user->password))throw ValidationException::withMessages(['email'=>'อีเมลหรือรหัสผ่านไม่ถูกต้อง']);
  if($r->is('api/*'))return response()->json(['user'=>$user,'token'=>$tokens->issue($user)]);
  Auth::login($user);$r->session()->regenerate();return redirect('/dashboard');
 }
 public function register(Request $r,TokenService $tokens){
  $d=$r->validate(['name'=>'required|string|max:100','email'=>'required|email|max:150|unique:users,email','phone'=>'required|regex:/^[0-9+ -]{8,20}$/|unique:users,phone','password'=>'required|string|min:8|confirmed']);
  $user=User::create(['name'=>$d['name'],'email'=>$d['email'],'phone'=>$d['phone'],'password'=>Hash::make($d['password']),'role'=>'user']);
  if($r->is('api/*'))return response()->json(['user'=>$user,'token'=>$tokens->issue($user)],201);
  Auth::login($user);$r->session()->regenerate();return redirect('/dashboard');
 }
 public function logout(Request $r,TokenService $tokens){
  if($r->is('api/*')){$tokens->revoke($r->bearerToken());return response()->json(['message'=>'ออกจากระบบแล้ว']);}
  Auth::logout();$r->session()->invalidate();$r->session()->regenerateToken();return redirect('/login');
 }
}
