<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::table('session_logs', function (Blueprint $table) {
            // Null preserves the original pay-after-playing behavior of old records.
            $table->unsignedSmallInteger('planned_minutes')->nullable();
            $table->decimal('quoted_amount', 10, 2)->default(0);
            $table->decimal('prepaid_amount', 10, 2)->default(0);
            $table->dateTime('paid_at')->nullable();
            $table->dateTime('scheduled_end_at')->nullable();
            $table->decimal('refund_amount', 10, 2)->default(0);
            $table->enum('refund_status', ['none', 'pending', 'paid'])->default('none');
            $table->dateTime('refunded_at')->nullable();
            $table->foreignId('refunded_by')->nullable()->constrained('users')->restrictOnDelete();
            $table->index(['refund_status', 'ended_at'], 'sessions_refund_status');
        });
    }

    public function down(): void {
        Schema::table('session_logs', function (Blueprint $table) {
            $table->dropForeign(['refunded_by']);
            $table->dropIndex('sessions_refund_status');
            $table->dropColumn(['planned_minutes', 'quoted_amount', 'prepaid_amount',
                'paid_at', 'scheduled_end_at', 'refund_amount', 'refund_status',
                'refunded_at', 'refunded_by']);
        });
    }
};
