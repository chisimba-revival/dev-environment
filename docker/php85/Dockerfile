FROM php:8.5.4-apache-bookworm

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

COPY config/php/php85.ini \
    /usr/local/etc/php/conf.d/chisimba.ini

RUN a2enmod rewrite

WORKDIR /var/www/html/ch

COPY docker/php74/chisimba-runtime-errors.php \
    /usr/local/lib/php/chisimba-runtime-errors.php

COPY docker/php74/99-chisimba-runtime-errors.ini \
    /usr/local/etc/php/conf.d/99-chisimba-runtime-errors.ini

COPY local-https/chisimba-forwarded-https.conf /etc/apache2/conf-available/chisimba-forwarded-https.conf
RUN a2enmod setenvif && a2enconf chisimba-forwarded-https
