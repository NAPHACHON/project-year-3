<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Package extends Model
{
    public $timestamps = false;

    protected $fillable = [
        'name',
        'hourly_rate',
        'created_at',
    ];

    public function stations(): HasMany
    {
        return $this->hasMany(GamingStation::class, 'package_id');
    }
}
