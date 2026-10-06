<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;

class GamingStation extends Model
{
    public $timestamps = false;

    protected $fillable = [
        'station_code',
        'package_id',
        'zone_name',
        'status',
        'specs_info',
        'created_at',
    ];

    public function package(): BelongsTo
    {
        return $this->belongsTo(Package::class, 'package_id');
    }

    public function sessions(): HasMany
    {
        return $this->hasMany(SessionLog::class, 'station_id');
    }

    public function activeSession(): HasOne
    {
        return $this->hasOne(SessionLog::class, 'station_id')->whereIn('status', ['reserved','active'])->latest('id');
    }
}
