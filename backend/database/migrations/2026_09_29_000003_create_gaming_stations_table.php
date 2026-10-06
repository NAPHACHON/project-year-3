<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
 public function up():void { Schema::create('gaming_stations',function(Blueprint $table){
$table->id();
$table->string('station_code',30)->unique();
$table->foreignId('package_id')->constrained('packages')->restrictOnDelete();
$table->string('zone_name',100);
$table->enum('status',['available','reserved','in_use','maintenance'])->default('available');
$table->string('specs_info')->nullable();
$table->timestamp('created_at')->useCurrent();
 }); }
 public function down():void { Schema::dropIfExists('gaming_stations'); }
};
