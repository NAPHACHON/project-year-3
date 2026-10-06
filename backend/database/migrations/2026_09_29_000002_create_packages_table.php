<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
 public function up():void { Schema::create('packages',function(Blueprint $table){
$table->id();
$table->string('name',100);
$table->decimal('hourly_rate',10,2);
$table->timestamp('created_at')->useCurrent();
 }); }
 public function down():void { Schema::dropIfExists('packages'); }
};
