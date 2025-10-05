#!/bin/bash
# Simple helper to copy files from a bitnami installation path into current dir.
set -e
SRC=${1:-/opt/bitnami/apps/suitecrm/htdocs}
DEST=${2:-./bitnami-suitecrm-files}
mkdir -p "$DEST"
echo "Copying files from $SRC to $DEST"
rsync -av --progress "$SRC/" "$DEST/"
echo "Create DB dump (you may need to run inside bitnami mysql container):"
echo "mysqldump -u root -p bitnami_suitecrm > suitecrm_backup.sql"
