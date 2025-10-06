```bash
#!/usr/bin/env bash
#
# setup.sh
# Production-ready installer helper for SuiteCRM on openSUSE (Leap/Tumbleweed/SLE).
# Installs prerequisites, downloads SuiteCRM (LTS 7.14.7 or Latest 8.9.0),
# prepares webroot & vhost, creates MariaDB DB/user, sets file permissions.
#
# Usage: sudo ./setup.sh
#
set -euo pipefail
IFS=$'\n\t'

# =============== CONFIG (edit if you want defaults) =================
DEFAULT_SUITECRM_PATH_BASE="/srv/www"     # base where site folders will be created
DEFAULT_DB_ROOT_USER="root"
DEFAULT_DB_ROOT_PASS=""                   # if empty, script will prompt to set
PHP_MIN_MEMORY="128M"
# Provided download URLs (from user)
LTS_URL="https://suitecrm.com/download/141/suite714/565364/suitecrm-7-14-7.zip"
LATEST_URL="https://suitecrm.com/download/166/suite89/565428/suitecrm-8-9-0.zip"
# =====================================================================

log() { printf "\e[32m[INFO]\e[0m %s\n" "$*"; }
warn() { printf "\e[33m[WARN]\e[0m %s\n" "$*"; }
err()  { printf "\e[31m[ERROR]\e[0m %s\n" "$*"; }

confirm() {
  read -r -p "$1 [y/N]: " ans
  case "$ans" in
    [yY][eE][sS]|[yY]) return 0;;
    *) return 1;;
  esac
}

require_root() {
  if [ "$EUID" -ne 0 ]; then
    err "This script must be run as root (or via sudo). Exiting."
    exit 1
  fi
}

# Ask minimal questions
require_root

read -r -p "Enter SuiteCRM site short name (used for directory & DB name, e.g. suitecrm1): " SITE_NAME
SITE_NAME="${SITE_NAME:-suitecrm}"
read -r -p "Install path base (default: ${DEFAULT_SUITECRM_PATH_BASE}): " SITE_BASE
SITE_BASE="${SITE_BASE:-$DEFAULT_SUITECRM_PATH_BASE}"
SITE_PATH="${SITE_BASE%/}/$SITE_NAME"

read -r -p "Enter the FQDN or hostname you will use for SuiteCRM (e.g. crm.example.com). If you don't have a domain, you can use server IP: " SITE_HOST
SITE_HOST="${SITE_HOST:-localhost}"

read -r -p "Select SuiteCRM version to download: (1) LTS 7.14.7  (2) Latest 8.9.0  [1/2]: " ver_choice
if [ "${ver_choice:-1}" = "2" ]; then
  DOWNLOAD_URL="$LATEST_URL"
  VER_LABEL="SuiteCRM 8.9.0 (Latest)"
else
  DOWNLOAD_URL="$LTS_URL"
  VER_LABEL="SuiteCRM 7.14.7 (LTS)"
fi

log "Preparing to install $VER_LABEL into $SITE_PATH (host: $SITE_HOST)"
if ! confirm "Continue?"; then
  log "User aborted."
  exit 0
fi

# Detect webserver (apache2/httpd or nginx)
WEBSERVER=""
if systemctl list-units --type=service --all | grep -q -E 'apache2|httpd'; then
  WEBSERVER="apache"
elif systemctl list-units --type=service --all | grep -q nginx; then
  WEBSERVER="nginx"
fi

if [ -z "$WEBSERVER" ]; then
  warn "No webserver detected. This script will install Apache (httpd) by default."
  if confirm "Install Apache (recommended for SuiteCRM) now?"; then
    zypper refresh
    zypper install -y apache2
    WEBSERVER="apache"
    systemctl enable --now apache2
  else
    err "No webserver available. You must have Apache or Nginx to host SuiteCRM."
    exit 1
  fi
else
  log "Detected webserver: $WEBSERVER"
fi

# Ensure MariaDB (mysql) installed and running
if ! command -v mysql >/dev/null 2>&1; then
  log "Installing MariaDB server (mariadb) ..."
  zypper refresh
  zypper install -y mariadb mariadb-tools
  systemctl enable --now mariadb
fi
# Ensure unzip, wget, php-cli and common packages
zypper refresh
COMMON_PKGS=(unzip wget curl)
for p in "${COMMON_PKGS[@]}"; do
  if ! rpm -q "$p" >/dev/null 2>&1; then
    log "Installing $p ..."
    zypper install -y "$p"
  fi
done

# Check PHP is installed; if not, install php8 and required extensions
PHP_CLI="$(command -v php || true)"
if [ -z "$PHP_CLI" ]; then
  log "PHP CLI not found. Installing php8 and common extensions..."
  zypper install -y php8 php8-mbstring php8-xml php8-json php8-zip php8-curl php8-imap php8-intl php8-pdo php8-mysql
  PHP_CLI="$(command -v php)"
fi
log "Using PHP CLI: $PHP_CLI (version: $($PHP_CLI -r 'echo PHP_VERSION;'))"

# Check required php.ini values
get_ini_val() {
  local key="$1"
  "$PHP_CLI" -r "echo ini_get('$key');" 2>/dev/null || echo ""
}
mem="$(get_ini_val memory_limit)"
if [ -z "$mem" ]; then mem="(unknown)"; fi
log "PHP memory_limit = $mem"
# If less than PHP_MIN_MEMORY, warn and offer to change php.ini
_mem_to_bytes() {
  local s="${1^^}"
  if [[ "$s" == *G ]]; then num=${s%G}; echo $((num * 1024 * 1024 * 1024))
  elif [[ "$s" == *M ]]; then num=${s%M}; echo $((num * 1024 * 1024))
  elif [[ "$s" == *K ]]; then num=${s%K}; echo $((num * 1024))
  else echo "$s"; fi
}
if [ "$mem" != "(unknown)" ]; then
  if [ "$(_mem_to_bytes "$mem")" -lt "$(_mem_to_bytes "$PHP_MIN_MEMORY")" ]; then
    warn "PHP memory_limit is less than $PHP_MIN_MEMORY. SuiteCRM recommends at least $PHP_MIN_MEMORY."
    if confirm "Attempt to set memory_limit=$PHP_MIN_MEMORY in CLI & FPM/Apache php.ini now?"; then
      PHP_INI="$($PHP_CLI -i | awk -F ' => ' '/Loaded Configuration File/ {print $2; exit}')"
      if [ -z "$PHP_INI" ]; then
        warn "Could not detect php.ini. Please edit your php.ini to set memory_limit=${PHP_MIN_MEMORY}"
      else
        sed -i.bak -r "s/^(memory_limit\s*=).*/\1 ${PHP_MIN_MEMORY}/I" "$PHP_INI" || echo "memory_limit = ${PHP_MIN_MEMORY}" >> "$PHP_INI"
        log "Edited $PHP_INI (backup: ${PHP_INI}.bak). Restarting webserver/php-fpm..."
        if [ "$WEBSERVER" = "apache" ]; then systemctl restart apache2; else systemctl restart php-fpm || true; fi
      fi
    fi
  fi
fi

# Check/install PHP extensions required for SuiteCRM
REQUIRED_EXT=(json xml mbstring zlib zip pcre imap curl)
missing_ext=()
phpmods_raw="$($PHP_CLI -m || true)"
for ext in "${REQUIRED_EXT[@]}"; do
  if ! printf '%s\n' "$phpmods_raw" | grep -q -i "^$ext\$"; then
    missing_ext+=("$ext")
  fi
done
if [ ${#missing_ext[@]} -gt 0 ]; then
  warn "Missing PHP CLI extensions: ${missing_ext[*]}"
  if confirm "Attempt to install common openSUSE php8 packages for those extensions now?"; then
    to_install=()
    for e in "${missing_ext[@]}"; do
      case "$e" in
        mbstring) to_install+=(php8-mbstring);;
        xml) to_install+=(php8-xml);;
        json) to_install+=(php8-json);;
        zlib) to_install+=(php8-zlib);;
        zip) to_install+=(php8-zip);;
        imap) to_install+=(php8-imap);;
        curl) to_install+=(php8-curl);;
        pcre) ;;
        *) to_install+=(php8-"$e");;
      esac
    done
    if [ ${#to_install[@]} -gt 0 ]; then
      zypper install -y "${to_install[@]}" || warn "Some php packages failed to install. Please install them manually."
      if [ "$WEBSERVER" = "apache" ]; then systemctl restart apache2; else systemctl restart php-fpm || true; fi
    fi
  else
    warn "Skipping automatic extension installation. SuiteCRM may fail if extensions missing in web SAPI."
  fi
fi

# Prepare DB: ask for root pass or prompt for one
read -r -s -p "Enter MariaDB root password (leave blank to use unix_socket / prompt to set): " DB_ROOT_PASS
echo
if [ -z "$DB_ROOT_PASS" ]; then
  log "Attempting to use unix_socket authentication or no password for root (typical on fresh installs)."
fi

# Check DB connection
DB_CONNECT_OK=false
if mysql -uroot -e "SELECT 1;" >/dev/null 2>&1; then DB_CONNECT_OK=true; fi
if ! $DB_CONNECT_OK && [ -n "$DB_ROOT_PASS" ]; then
  if mysql -uroot -p"$DB_ROOT_PASS" -e "SELECT 1;" >/dev/null 2>&1; then DB_CONNECT_OK=true; fi
fi

if ! $DB_CONNECT_OK; then
  warn "Cannot login to MariaDB as root with provided info. We'll try to run mysql_secure_installation and ask you to set root password."
  if confirm "Run mysql_secure_installation now and secure DB (recommended)?"; then
    mysql_secure_installation || warn "mysql_secure_installation did not complete; ensure MariaDB root access is available and re-run."
  else
    err "Cannot proceed without DB root access. Aborting."
    exit 1
  fi
fi

# Create DB and DB user
DB_NAME="${SITE_NAME}_db"
DB_USER="${SITE_NAME}_user"
DB_PASS="$(tr -dc 'A-Za-z0-9_@%+-' </dev/urandom | head -c 20 || echo 'ChangeMe123!')"

log "Creating MariaDB database ${DB_NAME} and user ${DB_USER} (with a generated password)"
# create with SQL; try root without password then with provided password
if mysql -uroot -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;" >/dev/null 2>&1; then
  mysql -uroot -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}'; GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost'; FLUSH PRIVILEGES;"
else
  mysql -uroot -p"$DB_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
  mysql -uroot -p"$DB_ROOT_PASS" -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}'; GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost'; FLUSH PRIVILEGES;"
fi
log "DB created and user granted."

# Create webroot directory
if [ -d "$SITE_PATH" ]; then
  warn "Directory $SITE_PATH already exists."
  if ! confirm "Proceed and overwrite contents under $SITE_PATH?"; then
    err "User aborted to avoid overwriting. Exiting."
    exit 1
  fi
else
  mkdir -p "$SITE_PATH"
fi

cd /tmp
ARCHIVE="/tmp/${SITE_NAME}-suitecrm.zip"
log "Downloading SuiteCRM package ($DOWNLOAD_URL) ..."
wget -O "$ARCHIVE" "$DOWNLOAD_URL"
log "Unpacking to $SITE_PATH ..."
unzip -q "$ARCHIVE" -d "$SITE_PATH.tmp"
# Many SuiteCRM zips contain a top-level folder; move its contents up
topdir="$(find "$SITE_PATH.tmp" -mindepth 1 -maxdepth 1 -type d | head -n1 || true)"
if [ -n "$topdir" ]; then
  # move contents into target directory
  rsync -a "$topdir"/ "$SITE_PATH"/
else
  rsync -a "$SITE_PATH.tmp"/ "$SITE_PATH"/
fi
rm -rf "$SITE_PATH.tmp" "$ARCHIVE"

# Set ownership & permissions: use webserver user (openSUSE commonly 'wwwrun' for Apache)
WEBUSER="wwwrun"
WEBGROUP="www"
if id wwwrun >/dev/null 2>&1; then
  WEBUSER="wwwrun"
  WEBGROUP="www"
elif id apache >/dev/null 2>&1; then
  WEBUSER="apache"
  WEBGROUP="apache"
elif id www-data >/dev/null 2>&1; then
  WEBUSER="www-data"
  WEBGROUP="www-data"
fi
log "Setting ownership to $WEBUSER:$WEBGROUP and recommended permissions..."
chown -R "$WEBUSER":"$WEBGROUP" "$SITE_PATH"
# directories 775, files 664
find "$SITE_PATH" -type d -print0 | xargs -0 -n200 chmod 775 || true
find "$SITE_PATH" -type f -print0 | xargs -0 -n200 chmod 664 || true

# Specific SuiteCRM writable dirs (best effort)
for d in config custom modules upload data cache; do
  if [ -d "$SITE_PATH/$d" ]; then
    chmod -R 775 "$SITE_PATH/$d" || true
    chown -R "$WEBUSER":"$WEBGROUP" "$SITE_PATH/$d" || true
  fi
done

# Create basic Apache virtualhost if Apache present
if [ "$WEBSERVER" = "apache" ]; then
  log "Creating Apache vhost for $SITE_HOST"
  VHOST_FILE="/etc/apache2/vhosts.d/${SITE_NAME}.conf"
  read -r -p "Serve SuiteCRM on port (default 80): " SITE_PORT
  SITE_PORT="${SITE_PORT:-80}"
  cat > "$VHOST_FILE" <<EOF
<VirtualHost *:${SITE_PORT}>
  ServerName ${SITE_HOST}
  DocumentRoot ${SITE_PATH}
  <Directory ${SITE_PATH}>
    AllowOverride All
    Require all granted
  </Directory>
  ErrorLog /var/log/apache2/${SITE_NAME}_error.log
  CustomLog /var/log/apache2/${SITE_NAME}_access.log combined
</VirtualHost>
EOF
  a2enmod rewrite || true
  systemctl restart apache2
  log "Apache vhost created: $VHOST_FILE (restarted apache2)."
else
  # NGINX vhost
  log "Creating Nginx server block for $SITE_HOST"
  read -r -p "Serve SuiteCRM on port (default 80): " SITE_PORT
  SITE_PORT="${SITE_PORT:-80}"
  NGINX_CONF="/etc/nginx/conf.d/${SITE_NAME}.conf"
  cat > "$NGINX_CONF" <<'EOF'
server {
    listen __PORT__;
    server_name __HOST__;
    root __ROOT__;
    index index.php index.html index.htm;

    client_max_body_size 50M;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        include /etc/nginx/fastcgi_params;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_pass unix:/run/php-fpm/www.sock;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        try_files $uri =404;
        expires max;
    }
}
EOF
  sed -i "s|__PORT__|${SITE_PORT}|g; s|__HOST__|${SITE_HOST}|g; s|__ROOT__|${SITE_PATH}|g" "$NGINX_CONF"
  systemctl restart nginx
  log "Nginx vhost created: $NGINX_CONF (restarted nginx)."
fi

# Write a minimal config_si.php for installer hints (not a full config.php)
cat > "${SITE_PATH}/config_si.php" <<EOF
<?php
\$sugar_config_si = array (
  'dbUSRData' =>
  array (
    'dbHostName' => 'localhost',
    'dbDatabaseName' => '${DB_NAME}',
    'dbUserName' => '${DB_USER}',
    'dbPassword' => '${DB_PASS}',
    'dbType' => 'mysql',
  ),
  'license' => '',
  'appEduMode' => false,
);
EOF
chown "$WEBUSER":"$WEBGROUP" "${SITE_PATH}/config_si.php"
chmod 660 "${SITE_PATH}/config_si.php"

log "SuiteCRM files placed and config_si.php prepared. Database connection details stored there for web installer use."

# Print final instructions
cat <<EOF

================ INFO — SuiteCRM Setup Prepared =====================

Instance directory:   ${SITE_PATH}
Site host / URL:      http${SITE_PORT+:}${SITE_PORT}://${SITE_HOST}:${SITE_PORT}   (if using port 80 omit :80)
Database name:        ${DB_NAME}
Database user:        ${DB_USER}
Database password:    ${DB_PASS}

What I did:
- Installed prerequisites (PHP packages, MariaDB, unzip/wget) if missing.
- Created MariaDB database and user (see above).
- Downloaded ${VER_LABEL} and extracted into ${SITE_PATH}.
- Set ownership to webserver user (${WEBUSER}:${WEBGROUP}) and set recommended permissions.
- Created a minimal config_si.php to prefill DB details for the web installer.
- Created a webserver vhost for ${SITE_HOST} and restarted $WEBSERVER.

Next steps (you must complete these in the browser):
1) Open the SuiteCRM installer in your browser:
   http://${SITE_HOST}${SITE_PORT:+:${SITE_PORT}}/
   (If served on port 80, you can omit :80)

2) Walk through the SuiteCRM web installer. Use the DB credentials shown above when prompted.
   - If installer reports missing PHP extensions, re-check php-fpm/apache modules and install missing packages.
   - If you encounter 403 on /api/graphql: ensure php.ini has no custom session.name or set it to PHPSESSID.

3) After the installer completes:
   - Remove install directory (if SuiteCRM suggests).
   - Backup config.php created by installer.
   - Secure file permissions as needed (this script already set typical recommended perms).

Notes & cautions:
- This script tries not to disturb existing services (ViciBox) by creating separate vhost and webroot. However,
  if ViciBox already uses port 80 on the same ServerName, you must provide a different hostname or port.
- For production: configure TLS (Let's Encrypt or other) — the script did NOT configure HTTPS.
- For SuiteCRM 8 there may be additional steps (OAuth keys, composer, etc.) depending on the package variant.
- If you want full automated install (skip web UI installer) I can add a best-effort automated installer step — ask for "automate installer".

If you want me to:
  1) Add automatic HTTPS with certbot (Let's Encrypt),
  2) Attempt a non-interactive final installer (complete admin user creation automatically),
  3) Harden permissions and SELinux/AppArmor notes,
choose any of the above.

====================================================================

EOF

log "Setup completed up to web-installer step. Open the URL above to finish SuiteCRM installation."

exit 0
```
