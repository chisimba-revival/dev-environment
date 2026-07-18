FROM php:8.2-apache-bookworm

# PHP 8.2 is deliberately pinned to Debian Bookworm.
#
# Do not copy the archived Bullseye repository override used by the
# frozen PHP 7.4 image. The official PHP 8.2 Bookworm image already
# contains a coherent Debian package configuration.

RUN set -eux; \
    apt-get update; \
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
        default-mysql-client \
    ; \
    docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
    ; \
    docker-php-ext-install -j"$(nproc)" \
        gd \
        mysqli \
        mbstring \
        xml \
        zip \
    ; \
    rm -rf /var/lib/apt/lists/*

COPY config/php/php82.ini \
    /usr/local/etc/php/conf.d/chisimba.ini

RUN a2enmod rewrite

WORKDIR /var/www/html/ch

# Retain the existing Chisimba runtime error capture policy during
# migration so PHP 7.4 and PHP 8.2 failures remain comparable.
COPY docker/php74/chisimba-runtime-errors.php \
    /usr/local/lib/php/chisimba-runtime-errors.php

COPY docker/php74/99-chisimba-runtime-errors.ini \
    /usr/local/etc/php/conf.d/99-chisimba-runtime-errors.ini
