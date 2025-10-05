FROM php:8.1-apache

ARG SUITECRM_VERSION=latest
ENV APACHE_DOCUMENT_ROOT=/var/www/html
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update          && apt-get install -y --no-install-recommends             ca-certificates curl wget unzip git build-essential g++ pkg-config             zlib1g-dev libzip-dev libicu-dev libxml2-dev             libpng-dev libwebp-dev libjpeg62-turbo-dev libjpeg-dev             libfreetype6-dev libfreetype-dev libonig-dev cron          && echo "=== Compiler versions ==="          && gcc --version || true          && g++ --version || true          && dpkg -l | grep libicu || true          && rm -rf /var/lib/apt/lists/*

RUN set -x && docker-php-ext-configure gd --with-freetype --with-jpeg

RUN set -x && docker-php-ext-install gd
RUN set -x && docker-php-ext-install mysqli
RUN set -x && docker-php-ext-install pdo pdo_mysql
RUN set -x && docker-php-ext-install zip
RUN set -x && docker-php-ext-install intl
RUN set -x && docker-php-ext-install mbstring
RUN set -x && docker-php-ext-install opcache xml soap

RUN a2enmod rewrite headers expires

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 80
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
