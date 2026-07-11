FROM php:5.6-apache

RUN set -eux; \
    printf '%s\n' \
      'deb [trusted=yes] http://archive.debian.org/debian stretch main' \
      'deb [trusted=yes] http://archive.debian.org/debian-security stretch/updates main' \
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
      zlib1g-dev \
      unzip \
      curl \
      rsync \
      mariadb-client \
    ; \
    docker-php-ext-configure gd \
      --with-freetype-dir=/usr/include/ \
      --with-jpeg-dir=/usr/include/; \
    docker-php-ext-install \
      gd \
      mysql \
      mysqli \
      mbstring \
      xml \
      zip; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    pear config-set auto_discover 1; \
    pear install -f MDB2-2.5.0b5; \
    pear install -a -f MDB2_Driver_mysql; \
    pear install -a -f MDB2_Schema; \
    pear install -a -f XML_Parser-1.3.4; \
    pear install -a -f Calendar-0.5.5

COPY config/php/legacy.ini /usr/local/etc/php/conf.d/chisimba.ini

RUN a2enmod rewrite

WORKDIR /var/www/html/ch
