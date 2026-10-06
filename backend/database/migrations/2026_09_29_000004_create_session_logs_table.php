<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
 public function up():void { Schema::create('session_logs',function(Blueprint $table){
$table->id();
$table->string('session_code',50)->unique();
$table->foreignId('user_id')->constrained('users')->restrictOnDelete();
$table->foreignId('station_id')->constrained('gaming_stations')->restrictOnDelete();
$table->unsignedInteger('minutes_used')->default(0);
$table->decimal('total_amount',10,2)->default(0);
$table->enum('status',['reserved','active','completed','cancelled','expired']);
$table->dateTime('reserved_at');
$table->dateTime('started_at')->nullable();
$table->dateTime('ended_at')->nullable();
$table->decimal('hourly_rate',10,2);
$table->unsignedInteger('free_minutes_used')->default(0);
$table->index(['station_id','status']);
$table->index(['user_id','status']);
 }); }
 public function down():void { Schema::dropIfExists('session_logs'); }
};
