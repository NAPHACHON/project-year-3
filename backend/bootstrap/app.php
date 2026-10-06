<?php
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Foundation\Configuration\Exceptions;
return Application::configure(basePath:dirname(__DIR__))
 ->withRouting(web:__DIR__.'/../routes/web.php',api:__DIR__.'/../routes/api.php',commands:__DIR__.'/../routes/console.php',health:'/up')
 ->withMiddleware(function(Middleware $middleware){
  $middleware->alias(['role'=>App\Http\Middleware\RoleCheck::class,'auth.token'=>App\Http\Middleware\TokenAuth::class]);
  $middleware->redirectGuestsTo('/login');
 })
 ->withExceptions(function(Exceptions $exceptions){
  $exceptions->shouldRenderJsonWhen(fn($request,$e)=>$request->is('api/*','web-api/*')||$request->expectsJson());
 })->create();
