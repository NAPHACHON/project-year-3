<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Http\Request;
class RoleCheck {
 public function handle(Request $request,Closure $next,string $role){
  abort_unless($request->user() && $request->user()->role===$role,403,'ไม่มีสิทธิ์ทำรายการนี้');
  return $next($request);
 }
}
