<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Http\Request;
use App\Services\TokenService;
class TokenAuth {
 public function handle(Request $request,Closure $next){
  $user=app(TokenService::class)->user($request->bearerToken());
  abort_unless($user,401,'กรุณาเข้าสู่ระบบใหม่');
  $request->setUserResolver(fn()=>$user);
  return $next($request);
 }
}
