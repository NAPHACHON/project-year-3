<?php
// Run after composer install. Reads .env rather than embedding credentials.
require __DIR__.'/vendor/autoload.php';
Dotenv\Dotenv::createImmutable(__DIR__)->safeLoad();
$name=$_ENV['DB_DATABASE']??'internet_cafe_v2_db';
if(!preg_match('/^[a-zA-Z0-9_]+$/D',$name)){fwrite(STDERR,"Invalid database name\n");exit(1);}
try{
 $pdo=new PDO('mysql:host='.($_ENV['DB_HOST']??'127.0.0.1').';port='.($_ENV['DB_PORT']??3306).';charset=utf8mb4',$_ENV['DB_USERNAME']??'root',$_ENV['DB_PASSWORD']??'',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
 $pdo->exec("CREATE DATABASE IF NOT EXISTS `{$name}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
 echo "Database ready: {$name}\n";
}catch(Throwable $e){fwrite(STDERR,"Cannot prepare database. Check MySQL and .env settings.\n");exit(1);}
