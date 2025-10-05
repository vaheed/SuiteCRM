FROM php:7.4-apache

ARG SUITECRM_VERSION=7.12.7
ENV APACHE_DOCUMENT_ROOT=/var/www/html

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpng-dev libjpeg-dev libzip-dev libicu-dev libxml2-dev git unzip curl cron \
  && docker-php-ext-configure gd --with-jpeg \
  && docker-php-ext-install -j$(nproc) gd mysqli pdo pdo_mysql zip intl mbstring opcache xml soap \
  && a2enmod rewrite headers expires

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
