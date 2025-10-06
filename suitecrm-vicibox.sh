#!/usr/bin/env bash
#
# setup-crm-production-opensuse.sh
#
# Production-ready SuiteCRM installer helper for openSUSE
#
set -euo pipefail
IFS=$'\n\t'

############################
# Defaults and URLs
############################
DEFAULT_SITE_BASE="/srv/www"
LTS_URL="https://suitecrm.com/download/141/suite714/565364/suitecrm-7-14-7.zip"
LATEST_URL="https://suitecrm.com/download/166/suite89/565428/suitecrm-8-9-0.zip"
PHP_MIN_MEMORY="128M"
DEFAULT_PORT=80

############################
# Logging
############################
log()  { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
err()  { printf '[ERROR] %s\n' "$*"; }

############################
# Helpers
############################
usage() {
  cat <<EOF
Usage: sudo bash $0 [options]

Options:
  --non-interactive        Run without interactive prompts
  --site-name NAME         Site short name (default: suitecrm)
  --host HOST              FQDN/IP to serve SuiteCRM (required in non-interactive)
  --version lts|latest     SuiteCRM version (default: lts)
  --site-base PATH         Base directory (default: ${DEFAULT_SITE_BASE})
  --port PORT              Port to serve on (default: ${DEFAULT_PORT})
  --db-root-pass PASS      MariaDB root password (if needed)
  --use-https yes|no       Attempt Let's Encrypt TLS (default: no)
  --email EMAIL            Email for Let's Encrypt registration (required if --use-https yes)
  --fresh                  Remove existing SuiteCRM and DB before installing
  -h, --help               Show this message
EOF
  exit 1
}

sql_escape_id()  { printf '%s' "$1" | sed "s/'/''/g"; }
sql_escape_str() { printf '%s' "$1" | sed "s/'/''/g"; }

############################
# Arg parsing
############################
NONINTERACTIVE=0
SITE_NAME=""
SITE_HOST=""
VER_CHOICE="lts"
SITE_BASE="$DEFAULT_SITE_BASE"
SITE_PORT="$DEFAULT_PORT"
DB_ROOT_PASS=""
USE_HTTPS="no"
LETS_EMAIL=""
FRESH_INSTALL=0

while (( "$#" )); do
  case "$1" in
    --non-interactive) NONINTERACTIVE=1; shift;;
    --site-name) SITE_NAME="$2"; shift 2;;
    --host) SITE_HOST="$2"; shift 2;;
    --version) VER_CHOICE="$2"; shift 2;;
    --site-base) SITE_BASE="$2"; shift 2;;
    --port) SITE_PORT="$2"; shift 2;;
    --db-root-pass) DB_ROOT_PASS="$2"; shift 2;;
    --use-https) USE_HTTPS="$2"; shift 2;;
    --email) LETS_EMAIL="$2"; shift 2;;
    --fresh) FRESH_INSTALL=1; shift;;
    -h|--help) usage;;
    *) err "Unknown argument: $1"; usage;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  err "Must run as root"
  exit 1
fi

# Interactive prompts if allowed
if [ "$NONINTERACTIVE" -eq 0 ]; then
  read -r -p "Site name [suitecrm]: " SITE_NAME
  SITE_NAME="${SITE_NAME:-suitecrm}"
  read -r -p "Site base [${SITE_BASE}]: " tmp
  SITE_BASE="${tmp:-$SITE_BASE}"
  read -r -p "Host (FQDN/IP): " SITE_HOST
  read -r -p "Version (1)LTS  (2)Latest [1/2]: " vsel
  VER_CHOICE=$([ "${vsel:-1}" = "2" ] && echo "latest" || echo "lts")
  read -r -p "Port [${DEFAULT_PORT}]: " tmp
  SITE_PORT="${tmp:-$SITE_PORT}"
  read -r -s -p "MariaDB root password (leave blank for socket): " DB_ROOT_PASS
  echo
  read -r -p "Use HTTPS? (yes/no) [no]: " uhttps
  USE_HTTPS="${uhttps:-no}"
  read -r -p "Fresh install (remove existing SuiteCRM)? (yes/no) [no]: " fresh
  FRESH_INSTALL=$([ "$fresh" = "yes" ] && echo 1 || echo 0)
  if [ "$USE_HTTPS" = "yes" ]; then
    read -r -p "Email for Let's Encrypt: " LETS_EMAIL
  fi
else
  SITE_NAME="${SITE_NAME:-suitecrm}"
  if [ -z "$SITE_HOST" ]; then
    err "--host required in non-interactive mode"; exit 1
  fi
  VER_CHOICE="${VER_CHOICE:-lts}"
  SITE_BASE="${SITE_BASE:-$DEFAULT_SITE_BASE}"
  SITE_PORT="${SITE_PORT:-$DEFAULT_PORT}"
  USE_HTTPS="${USE_HTTPS:-no}"
  if [ "$USE_HTTPS" = "yes" ] && [ -z "$LETS_EMAIL" ]; then
    err "--email required when using --use-https yes"; exit 1
  fi
fi

DOWNLOAD_URL="${LTS_URL}"
[ "$VER_CHOICE" = "latest" ] && DOWNLOAD_URL="${LATEST_URL}"

SITE_PATH="${SITE_BASE%/}/${SITE_NAME}"
DB_NAME="${SITE_NAME}_db"
DB_USER="${SITE_NAME}_user"
DB_PASS="$(tr -dc 'A-Za-z0-9_@%+-' </dev/urandom | head -c 20 || echo 'ChangeMe123!')"

log "Preparing SuiteCRM installation..."
log "Site: ${SITE_NAME}, Host: ${SITE_HOST}, Port: ${SITE_PORT}, Version: ${VER_CHOICE}"

############################
# Fresh install cleanup
############################
if [ "$FRESH_INSTALL" -eq 1 ]; then
  warn "Fresh install requested. Removing existing installation if present..."
  [ -d "$SITE_PATH" ] && rm -rf "$SITE_PATH" && log "Removed old files at $SITE_PATH"

  MYSQL_CMD=""
  if mysql -uroot -e "SELECT 1;" >/dev/null 2>&1; then MYSQL_CMD='mysql -uroot'
  elif [ -n "$DB_ROOT_PASS" ] && mysql -uroot -p"${DB_ROOT_PASS}" -e "SELECT 1;" >/dev/null 2>&1; then MYSQL_CMD="mysql -uroot -p${DB_ROOT_PASS}"; fi

  if [ -n "$MYSQL_CMD" ]; then
    echo "DROP DATABASE IF EXISTS \`${DB_NAME}\`;" | eval "$MYSQL_CMD" && log "Dropped old database $DB_NAME"
    echo "DROP USER IF EXISTS '${DB_USER}'@'localhost';" | eval "$MYSQL_CMD" && log "Dropped old DB user $DB_USER"
  else
    warn "Cannot access MariaDB to remove old DB/user. Remove manually if exists."
  fi

  # Remove old Apache vhost
  VH_FILE="/etc/apache2/vhosts.d/${SITE_NAME}.conf"
  [ -f "$VH_FILE" ] && rm -f "$VH_FILE" && log "Removed old vhost $VH_FILE"
fi

############################
# Update system and install packages
############################
log "Refreshing repositories and updating system..."
zypper refresh -s >/dev/null 2>&1 || true
zypper update -y || warn "System update failed, continue"

# Determine PHP packages compatible with openSUSE
AVAILABLE_PHP_PACKAGES=(php8 php8-mbstring php8-xmlreader php8-zip php8-curl php8-imap php8-mysql apache2)
for p in "${AVAILABLE_PHP_PACKAGES[@]}"; do
  rpm -q "$p" >/dev/null 2>&1 || zypper install -y "$p" || warn "Package $p failed"
done

systemctl enable --now apache2 || warn "Cannot start apache2"

############################
# Detect MariaDB root login
############################
MYSQL_CMD=""
if mysql -uroot -e "SELECT 1;" >/dev/null 2>&1; then
  MYSQL_CMD='mysql -uroot'
elif [ -n "$DB_ROOT_PASS" ] && mysql -uroot -p"${DB_ROOT_PASS}" -e "SELECT 1;" >/dev/null 2>&1; then
  MYSQL_CMD="mysql -uroot -p${DB_ROOT_PASS}"
fi

if [ -n "$MYSQL_CMD" ]; then
  log "Creating DB and user..."
  SAFE_DB="$(sql_escape_id "${DB_NAME}")"
  SAFE_USER="$(sql_escape_str "${DB_USER}")"
  SAFE_PASS="$(sql_escape_str "${DB_PASS}")"
  SQL="CREATE DATABASE IF NOT EXISTS \`${SAFE_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
       CREATE USER IF NOT EXISTS '${SAFE_USER}'@'localhost' IDENTIFIED BY '${SAFE_PASS}';
       GRANT ALL PRIVILEGES ON \`${SAFE_DB}\`.* TO '${SAFE_USER}'@'localhost';
       FLUSH PRIVILEGES;"
  echo "$SQL" | eval "$MYSQL_CMD" || warn "DB creation failed. SQL:\n$SQL"
else
  warn "No MariaDB root access. Create DB/user manually."
fi

############################
# Download & extract SuiteCRM
############################
log "Downloading SuiteCRM..."
TMPDIR="$(mktemp -d)"
ARCHIVE="${TMPDIR}/${SITE_NAME}.zip"
wget -O "$ARCHIVE" "$DOWNLOAD_URL" || { err "Download failed"; exit 1; }

log "Extracting to $SITE_PATH..."
mkdir -p "$SITE_PATH"
unzip -q "$ARCHIVE" -d "$TMPDIR/extract"
TOPDIR="$(find "$TMPDIR/extract" -mindepth 1 -maxdepth 1 -type d | head -n1)"
[ -n "$TOPDIR" ] && rsync -a "$TOPDIR/" "$SITE_PATH/" || rsync -a "$TMPDIR/extract/" "$SITE_PATH/"
rm -rf "$TMPDIR"

############################
# Permissions
############################
WEBUSER="wwwrun"; WEBGROUP="www"
id wwwrun >/dev/null 2>&1 || { WEBUSER="apache"; WEBGROUP="apache"; }
id apache >/dev/null 2>&1 && { WEBUSER="apache"; WEBGROUP="apache"; }

chown -R "$WEBUSER:$WEBGROUP" "$SITE_PATH"
find "$SITE_PATH" -type d -exec chmod 775 {} +
find "$SITE_PATH" -type f -exec chmod 664 {} +
for d in config custom modules upload data cache; do
  [ -d "$SITE_PATH/$d" ] && chmod -R 775 "$SITE_PATH/$d" && chown -R "$WEBUSER:$WEBGROUP" "$SITE_PATH/$d"
done

############################
# Apache vhost
############################
VH_DIR="/etc/apache2/vhosts.d"
mkdir -p "$VH_DIR"
VHOST_FILE="${VH_DIR}/${SITE_NAME}.conf"
if [ ! -f "$VHOST_FILE" ]; then
  log "Creating vhost $VHOST_FILE"
  cat >"$VHOST_FILE" <<EOF
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
  a2enmod rewrite >/dev/null 2>&1 || true
  systemctl restart apache2 || warn "Restart apache2 manually"
else
  warn "Vhost exists: $VHOST_FILE"
fi

############################
# config_si.php for web installer
############################
if [ -n "$MYSQL_CMD" ]; then
  cat > "$SITE_PATH/config_si.php" <<EOF
<?php
\$sugar_config_si = array (
  'dbUSRData' => array (
    'dbHostName' => 'localhost',
    'dbDatabaseName' => '${DB_NAME}',
    'dbUserName' => '${DB_USER}',
    'dbPassword' => '${DB_PASS}',
    'dbType' => 'mysql',
  ),
);
EOF
  chown "$WEBUSER:$WEBGROUP" "$SITE_PATH/config_si.php"
  chmod 660 "$SITE_PATH/config_si.php"
fi

############################
# Optional Let's Encrypt TLS
############################
if [ "$USE_HTTPS" = "yes" ]; then
  command -v certbot >/dev/null 2>&1 || zypper install -y certbot || warn "Install certbot manually"
  [ -f "$VHOST_FILE" ] && WEBROOT="$SITE_PATH" && certbot certonly --agree-tos --non-interactive --email "$LETS_EMAIL" --webroot -w "$WEBROOT" -d "$SITE_HOST" || warn "Cannot issue cert, check certbot"
fi

############################
# Summary
############################
cat <<EOF

=== SuiteCRM installation prepared ===
Site directory:  ${SITE_PATH}
Web host:        ${SITE_HOST}
Port:            ${SITE_PORT}
Database name:   ${DB_NAME}
Database user:   ${DB_USER}
Database pass:   ${DB_PASS}

Next steps:
1. Open web installer: http://${SITE_HOST}${SITE_PORT:+:${SITE_PORT}}/
2. Complete web installer.
3. Configure TLS if enabled.
4. Verify PHP extensions for web SAPI.
5. Harden permissions and MariaDB root.

EOF

exit 0
