FROM php:8.3-apache

# --- Dependencias de sistema + extensiones PHP requeridas por Drupal 11 ---
RUN apt-get update && apt-get install -y --no-install-recommends \
        git unzip curl default-mysql-client \
        libpng-dev libjpeg-dev libfreetype6-dev libwebp-dev \
        libzip-dev libicu-dev libonig-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j"$(nproc)" gd pdo pdo_mysql mysqli opcache zip intl \
    && rm -rf /var/lib/apt/lists/*

# --- Forzar IPv4: evita timeouts a github.com/codeload en OrbStack ---
RUN echo 'precedence ::ffff:0:0/96 100' >> /etc/gai.conf

# --- Composer + timeout amplio ---
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
ENV COMPOSER_PROCESS_TIMEOUT=2000

# --- Apache: docroot en /var/www/html/web + mod_rewrite ---
ENV APACHE_DOCUMENT_ROOT=/var/www/html/web
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
    && sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf \
    && a2enmod rewrite

# --- Ajustes PHP recomendados para Drupal ---
RUN { \
      echo 'memory_limit=256M'; \
      echo 'upload_max_filesize=64M'; \
      echo 'post_max_size=64M'; \
      echo 'max_execution_time=120'; \
      echo 'opcache.enable=1'; \
      echo 'opcache.memory_consumption=128'; \
    } > /usr/local/etc/php/conf.d/drupal.ini

WORKDIR /var/www/html

# --- Instalar dependencias con reintentos (capa cacheable) ---
COPY composer.json ./
COPY composer.lock* ./
RUN set -eux; \
    if [ -f composer.lock ]; then C="install"; else C="update"; fi; \
    OK=0; \
    for i in 1 2 3; do \
      if composer $C --no-dev --no-interaction --no-progress --prefer-dist; then OK=1; break; fi; \
      echo ">>> Fallo el intento $i/3, reintentando..."; sleep 8; \
    done; \
    [ "$OK" = "1" ] || { echo ">>> Composer fallo tras 3 intentos"; exit 1; }

# --- Copiar el resto del proyecto (settings.php, custom, config) ---
COPY . .
RUN composer install --no-dev --no-interaction --no-progress --prefer-dist \
    && mkdir -p web/sites/default/files web/sites/default/private \
    && chown -R www-data:www-data web/sites web/modules web/themes config

EXPOSE 80
