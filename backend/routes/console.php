<?php
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;
Artisan::command('cafe:expire',function(){ $this->info('Expired: '.app(App\Services\CafeService::class)->expireReservations()); });
Schedule::command('cafe:expire')->everyMinute()->withoutOverlapping();
