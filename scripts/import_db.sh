#!/bin/bash
# Usage: scripts/import_db.sh suitecrm_backup.sql
set -e
SQL_FILE=${1:-suitecrm_backup.sql}
if [ ! -f "$SQL_FILE" ]; then
  echo "SQL file $SQL_FILE not found"
  exit 1
fi
echo "Importing $SQL_FILE into container 'suitecrm_db' (must be running)"
docker cp "$SQL_FILE" suitecrm_db:/tmp/
docker exec -i suitecrm_db bash -c "mysql -u root -p\"$MYSQL_ROOT_PASSWORD\" $MYSQL_DATABASE < /tmp/$(basename $SQL_FILE)"
