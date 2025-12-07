#!/usr/bin/env bash
#
# EXAMPLE pre-backup hook for MySQL/MariaDB.
# This script is NOT executable by default.
# To use it:
#   1. Customize the credentials/command as needed.
#   2. chmod +x /etc/restic-backup/pre-backup.d/10-mysql-dump-example.sh
#
set -euo pipefail

BACKUP_DIR="/var/backups/mysql"
mkdir -p "$BACKUP_DIR"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
DUMP_FILE="$BACKUP_DIR/all-databases-$TIMESTAMP.sql.gz"

echo "Running example MySQL dump to $DUMP_FILE"

# Example using defaults/socket auth (e.g. for root via unix socket):
# Adjust as needed for your environment.
mysqldump --all-databases | gzip -c > "$DUMP_FILE"

# Optionally, remove old dumps (e.g. keep last 7)
ls -1t "$BACKUP_DIR"/all-databases-*.sql.gz 2>/dev/null | tail -n +8 | xargs -r rm -f

echo "MySQL dump complete."
