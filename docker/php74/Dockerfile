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

RUN set -eux; \
    pear config-set auto_discover 1; \
    pear install -f MDB2-2.5.0b5; \
    pear install -a -f MDB2_Driver_mysql; \
    pear install -a -f MDB2_Driver_mysqli; \
    pear install -a -f MDB2_Schema; \
    pear install -a -f XML_Parser-1.3.4; \
    pear install -a -f Calendar-0.5.5
    
# Patch legacy PEAR MDB2 code for PHP 7.4 compatibility.
#
# MDB2_Driver_mysql 1.4.1 and MDB2_Driver_mysqli 1.4.1 still contain
# PHP 4 object-construction syntax ("=& new" and "= &new"), which PHP 7
# cannot parse. MDB2::parseDSN() also calls count() on a string or null.
RUN set -eux; \
    sed -i \
      -e 's/\([[:space:]]\)=&[[:space:]]*new[[:space:]]/\1= new /g' \
      -e 's/\([[:space:]]\)=[[:space:]]*&new[[:space:]]/\1= new /g' \
      /usr/local/lib/php/MDB2/Driver/mysql.php \
      /usr/local/lib/php/MDB2/Driver/mysqli.php; \
    sed -i \
      's/if (!count($dsn)) {/if ($dsn === null || $dsn === "") {/' \
      /usr/local/lib/php/MDB2.php; \
    php -l /usr/local/lib/php/MDB2.php; \
    php -l /usr/local/lib/php/MDB2/Driver/mysql.php; \
    php -l /usr/local/lib/php/MDB2/Driver/mysqli.php; \
    php -l /usr/local/lib/php/MDB2/Schema.php

COPY config/php/php74.ini /usr/local/etc/php/conf.d/chisimba.ini

RUN a2enmod rewrite

WORKDIR /var/www/html/ch
