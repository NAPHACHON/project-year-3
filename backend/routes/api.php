<?php
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\{CafeController,AuthController};
$apiStatus = fn() => response()->json([
 'status' => 'ok', 'service' => 'CyberCafe REST API',
 'base_url' => url('/api/v1'), 'documentation' => url('/api-docs'),
 'message' => 'API is running. Login uses POST /api/v1/auth/login.',
]);
Route::get('/', $apiStatus);
Route::get('/v1', $apiStatus);
Route::get('/v1/health', $apiStatus);
Route::prefix('v1')->group(function(){
 Route::post('/auth/login',[AuthController::class,'login'])->middleware('throttle:10,1');
 Route::post('/auth/register',[AuthController::class,'register'])->middleware('throttle:5,1');
 Route::middleware('auth.token')->group(function(){
 Route::post('/auth/logout',[AuthController::class,'logout']);
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
