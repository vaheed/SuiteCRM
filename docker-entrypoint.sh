#!/bin/bash
set -e

# If web root empty, download SuiteCRM
if [ -z "$(ls -A /var/www/html 2>/dev/null)" ]; then
  echo "Web root empty — downloading SuiteCRM..."
  SUITE_VERSION="${SUITECRM_VERSION:-latest}"
  if [ "$SUITE_VERSION" = "latest" ]; then
    # default to 8.x branch if PHP >= 8, otherwise use 7.12
    PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
    if [[ "$PHP_VERSION" == 8.* ]]; then
      DOWNLOAD_URL="https://github.com/salesagility/SuiteCRM/archive/refs/heads/8.x.zip"
    else
      DOWNLOAD_URL="https://github.com/salesagility/SuiteCRM/archive/refs/tags/v7.12.7.zip"
    fi
  else
    # allow explicit tag or URL
    if [[ "$SUITE_VERSION" =~ ^https?:// ]]; then
      DOWNLOAD_URL="$SUITE_VERSION"
    else
      DOWNLOAD_URL="https://github.com/salesagility/SuiteCRM/archive/refs/tags/${SUITE_VERSION}.zip"
    fi
  fi

  echo "Downloading $DOWNLOAD_URL"
  curl -fsSL "$DOWNLOAD_URL" -o /tmp/suitecrm.zip || true
  if [ -f /tmp/suitecrm.zip ]; then
    unzip /tmp/suitecrm.zip -d /tmp
    # find the extracted dir (SuiteCRM-*)
    EXDIR=$(ls -d /tmp/SuiteCRM-* | head -n1)
    if [ -d "$EXDIR" ]; then
      mv "$EXDIR"/* /var/www/html/
      rm -rf "$EXDIR"
    fi
    rm -f /tmp/suitecrm.zip
    chown -R www-data:www-data /var/www/html
  else
    echo "Warning: couldn't download SuiteCRM. Mount your files into /var/www/html"
  fi
fi

# Ensure permissions
chown -R www-data:www-data /var/www/html || true

exec "$@"
