<?php

// Conexión a la base de datos vía variables de entorno (inyectadas por Docker/Dokploy).
$databases['default']['default'] = [
  'driver' => 'mysql',
  'host' => getenv('DB_HOST') ?: 'mariadb',
  'port' => getenv('DB_PORT') ?: '3306',
  'database' => getenv('DB_NAME'),
  'username' => getenv('DB_USER'),
  'password' => getenv('DB_PASSWORD'),
  'prefix' => '',
  'collation' => 'utf8mb4_general_ci',
];

// Semilla de seguridad (no debe cambiar entre despliegues del mismo ambiente).
$settings['hash_salt'] = getenv('DRUPAL_HASH_SALT');

// Directorio de configuración exportable (config split dev/qa se maneja luego).
$settings['config_sync_directory'] = '../config/sync';

// Rutas de archivos.
$settings['file_private_path'] = 'sites/default/private';

// Detrás de Traefik (Dokploy) confiamos en el proxy inverso.
$settings['reverse_proxy'] = TRUE;
if (isset($_SERVER['REMOTE_ADDR'])) {
  $settings['reverse_proxy_addresses'] = [$_SERVER['REMOTE_ADDR']];
}

// TEMPORAL: dominios *.traefik.me. En QA/prod se restringe a los dominios reales.
$settings['trusted_host_patterns'] = ['.*'];
