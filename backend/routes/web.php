<?php
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\{CafeController,AuthController};

Route::get('/',fn()=>redirect('/dashboard'));
Route::middleware('guest')->group(function(){
 Route::get('/login',fn()=>view('auth',['register'=>false]))->name('login');
 Route::get('/register',fn()=>view('auth',['register'=>true]));
 Route::post('/login',[AuthController::class,'login'])->middleware('throttle:10,1');
 Route::post('/register',[AuthController::class,'register'])->middleware('throttle:5,1');
});
Route::middleware('auth')->group(function(){
 Route::get('/dashboard',fn()=>view('dashboard'));
 Route::get('/admin/dashboard',fn()=>redirect('/dashboard'))->middleware('role:admin');
 Route::get('/user/dashboard',fn()=>redirect('/dashboard'));
 Route::post('/logout',[AuthController::class,'logout']);
 Route::prefix('web-api')->group(function(){
Route::get('/data',[CafeController::class,'data']);
Route::post('/bookings',[CafeController::class,'book']);
Route::post('/sessions/{id}/cancel',[CafeController::class,'cancel']);
Route::get('/sessions/{id}/settlement',[CafeController::class,'preview']);
Route::post('/sessions/{id}/end',[CafeController::class,'end']);
Route::middleware('role:admin')->prefix('admin')->group(function(){
 Route::post('/bookings',[CafeController::class,'reserveForMember']);
 Route::post('/sessions/{id}/start',[CafeController::class,'start']);
 Route::post('/sessions/{id}/finish',[CafeController::class,'finish']);
 Route::post('/sessions/{id}/refund',[CafeController::class,'refund']);
 Route::patch('/stations/{id}/status',[CafeController::class,'status']);
 Route::post('/stations',[CafeController::class,'station']);
 Route::put('/stations/{id}',[CafeController::class,'station']);
 Route::post('/packages',[CafeController::class,'package']);
 Route::put('/packages/{id}',[CafeController::class,'package']);
});
 });
});
Route::get('/api-docs', function () {
 $document = json_decode(file_get_contents(base_path('api-docs.json')), true, 512, JSON_THROW_ON_ERROR);
 return response()->json($document);
});
Route::get('/flutter', fn()=>view('member'))->middleware('auth');
Route::get('/flutter/index.html', fn()=>redirect('/flutter'))->middleware('auth');
