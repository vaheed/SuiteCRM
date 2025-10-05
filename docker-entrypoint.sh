#!/bin/bash
set -e

if [ -n "$SUITECRM_URL" ]; then
  DOWNLOAD_URL="$SUITECRM_URL"
else
  case "${SUITECRM_VERSION:-latest}" in
    latest|8|8.*)
      if [[ "${SUITECRM_VERSION}" =~ ^8([.]|$) ]]; then
        DOWNLOAD_URL="https://suitecrm.com/download/166/suite89/565428/suitecrm-8-9-0.zip"
      else
        DOWNLOAD_URL="https://github.com/salesagility/SuiteCRM/archive/refs/heads/8.x.zip"
      fi
      ;;
    7*|7.*)
      if [[ "${SUITECRM_VERSION}" == "7.14.7" ]]; then
        DOWNLOAD_URL="https://suitecrm.com/download/141/suite714/565364/suitecrm-7-14-7.zip"
      else
        DOWNLOAD_URL="https://github.com/salesagility/SuiteCRM/archive/refs/tags/v7.12.7.zip"
      fi
      ;;
    *)
      DOWNLOAD_URL="https://github.com/salesagility/SuiteCRM/archive/refs/heads/8.x.zip"
      ;;
  esac
fi

if [ -z "$(ls -A /var/www/html 2>/dev/null)" ]; then
  echo "Web root empty — attempting download from: $DOWNLOAD_URL"
  mkdir -p /tmp/suitecrm_dl
  curl -fsSL "$DOWNLOAD_URL" -o /tmp/suitecrm_dl/suitecrm.zip || true
  if [ -f /tmp/suitecrm_dl/suitecrm.zip" ]; then
    unzip /tmp/suitecrm_dl/suitecrm.zip -d /tmp/suitecrm_dl
    EXDIR=$(find /tmp/suitecrm_dl -maxdepth 1 -type d -name 'SuiteCRM*' -print -quit)
    if [ -z "$EXDIR" ]; then
      EXDIR=$(find /tmp/suitecrm_dl -maxdepth 1 -type d ! -path /tmp/suitecrm_dl -print -quit)
    fi
    if [ -n "$EXDIR" ]; then
      shopt -s dotglob
      mv "$EXDIR"/* /var/www/html/
      shopt -u dotglob
    else
      mv /tmp/suitecrm_dl/* /var/www/html/ || true
    fi
    rm -rf /tmp/suitecrm_dl
    chown -R www-data:www-data /var/www/html
  else
    echo "Warning: couldn't download SuiteCRM. Mount your files into /var/www/html or set SUITECRM_URL."
  fi
fi

chown -R www-data:www-data /var/www/html || true

exec "$@"
