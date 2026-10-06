<?php
return [
 'default'=>env('DB_CONNECTION','mysql'),
 'connections'=>[
  'mysql'=>['driver'=>'mysql','host'=>env('DB_HOST','127.0.0.1'),'port'=>env('DB_PORT',3306),'database'=>env('DB_DATABASE','internet_cafe_v2_db'),'username'=>env('DB_USERNAME','root'),'password'=>env('DB_PASSWORD',''),'unix_socket'=>env('DB_SOCKET',''),'charset'=>'utf8mb4','collation'=>'utf8mb4_unicode_ci','prefix'=>'','prefix_indexes'=>true,'strict'=>true,'engine'=>'InnoDB'],
  'sqlite'=>['driver'=>'sqlite','database'=>env('DB_DATABASE',':memory:'),'prefix'=>'','foreign_key_constraints'=>true],
 ],
 'migrations'=>['table'=>'migrations','update_date_on_publish'=>true],
];
