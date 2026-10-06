<?php
namespace App\Services;

class Billing {
    // Started minutes are billed using server timestamps.
    public static function minutes(int $start, int $end): int {
        return max(0, (int) ceil(($end - $start) / 60));
    }

    public static function cents(string $amount): int {
        return (int) round((float) $amount * 100);
    }

    public static function money(int $cents): string {
        return number_format($cents / 100, 2, '.', '');
    }

    public static function amount(int $minutes, int $free, string $hourly): string {
        return self::money((int) round(max(0, $minutes - $free) * self::cents($hourly) / 60));
    }

    public static function settlement(int $minutes, int $free, string $hourly, string $prepaid): array {
        $free = min(max(0, $minutes), max(0, $free));
        $total = self::amount($minutes, $free, $hourly);
        $difference = self::cents($prepaid) - self::cents($total);
        return ['minutes_used' => $minutes, 'free_minutes_used' => $free,
            'total_amount' => $total, 'prepaid_amount' => $prepaid,
            'refund_amount' => self::money(max(0, $difference)),
            'balance_due' => self::money(max(0, -$difference))];
    }

    public static function availableFreeMinutes(int $paidMinutes, int $usedFree): int {
        return max(0, intdiv(max(0, $paidMinutes), 600) * 60 - $usedFree);
    }
}
