<?php

// Run before Composer or Artisan; no vendor files or database are required.
$directories = [
    'bootstrap/cache',
    'storage/app/private',
    'storage/app/public',
    'storage/framework/cache/data',
    'storage/framework/sessions',
    'storage/framework/views',
    'storage/logs',
];

foreach ($directories as $directory) {
    $path = __DIR__.DIRECTORY_SEPARATOR.str_replace('/', DIRECTORY_SEPARATOR, $directory);

    if (!is_dir($path) && !@mkdir($path, 0775, true) && !is_dir($path)) {
        fwrite(STDERR, "Cannot create runtime directory: {$path}".PHP_EOL);
        fwrite(STDERR, "Check that the project folder is writable, then retry.".PHP_EOL);
        exit(1);
    }

    if (!is_writable($path)) {
        fwrite(STDERR, "Runtime directory is not writable: {$path}".PHP_EOL);
        fwrite(STDERR, "Give your current user write access to this folder, then retry.".PHP_EOL);
        exit(1);
    }
}
