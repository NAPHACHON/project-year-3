<?php
namespace App\Services;
use App\Models\User;
use Illuminate\Support\Facades\Cache;
class TokenService {
 public function issue(User $user): string {
  $token=bin2hex(random_bytes(32));
  Cache::put('api_token_'.hash('sha256',$token),$user->id,now()->addDays(7));
  return $token;
 }
 public function user(?string $token): ?User {
  if(!$token || !preg_match('/^[a-f0-9]{64}$/D',$token)) return null;
  $id=Cache::get('api_token_'.hash('sha256',$token));
  return $id ? User::find($id) : null;
 }
 public function revoke(?string $token): void { if($token) Cache::forget('api_token_'.hash('sha256',$token)); }
}
