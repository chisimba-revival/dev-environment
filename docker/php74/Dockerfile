FROM php:7.4-apache

# The current archived php:7.4-apache image is based on Debian Bullseye.
# Bullseye is archived, so use the matching archived repositories rather
# than mixing the image's Bullseye packages with Debian Buster packages.
RUN set -eux; \
    printf '%s\n' \
      'deb [trusted=yes] http://archive.debian.org/debian bullseye main' \
      'deb http://security.debian.org/debian-security bullseye-security main' \
      > /etc/apt/sources.list; \
    apt-get \
      -o Acquire::Check-Valid-Until=false \
      -o Acquire::AllowInsecureRepositories=true \
      update; \
    apt-get install -y --no-install-recommends \
      libpng-dev \
      libjpeg62-turbo-dev \
      libfreetype6-dev \
      libxml2-dev \
      libzip-dev \
      libonig-dev \
      zlib1g-dev \
      unzip \
      curl \
      rsync \
      mariadb-client \
    ; \
    docker-php-ext-configure gd \
      --with-freetype \
      --with-jpeg; \
    docker-php-ext-install \
      gd \
      mysqli \
      mbstring \
      xml \
      zip; \
    rm -rf /var/lib/apt/lists/*


COPY config/php/php74.ini /usr/local/etc/php/conf.d/chisimba.ini

RUN a2enmod rewrite

WORKDIR /var/www/html/ch

# Chisimba PHP 7.4 runtime error policy
COPY docker/php74/chisimba-runtime-errors.php /usr/local/lib/php/chisimba-runtime-errors.php
COPY docker/php74/99-chisimba-runtime-errors.ini /usr/local/etc/php/conf.d/99-chisimba-runtime-errors.ini
