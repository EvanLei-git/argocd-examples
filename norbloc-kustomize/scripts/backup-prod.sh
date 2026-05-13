#!/bin/bash
set -euo pipefail

# This script creates a backup of the MariaDB production database.
# It acts like a cronjob script, keeping a limit of 3 backups (3 days).

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_DIR="./backups/mariadb_backup_$TIMESTAMP"

mkdir -p "$BACKUP_DIR"

echo "🔍 Finding Production MariaDB pod..."
PROD_DB_POD=$(kubectl get pods -n wordpress -l app=mariadb | grep "prod-" | grep Running | awk '{print $1}' | head -n 1)

if [ -z "$PROD_DB_POD" ]; then
  echo "❌ Error: Could not find running MariaDB Production pod."
  exit 1
fi

echo "✅ Found DB Prod: $PROD_DB_POD"

echo "🚀 Backing up MariaDB Database..."
# Get DB password securely
DB_PASSWORD=$(kubectl get secret mysql-pass-prod -n wordpress -o jsonpath="{.data.password}" | base64 --decode)
kubectl exec "$PROD_DB_POD" -n wordpress -- mysqldump -u root -p"$DB_PASSWORD" wordpress > "$BACKUP_DIR/database.sql"

echo "🎉 Backup complete! Saved to $BACKUP_DIR"

echo "🧹 Enforcing 3-day retention policy (keeping newest 3 backups)..."
BACKUP_COUNT=$(ls -1d ./backups/mariadb_backup_* 2>/dev/null | wc -l || true)
if [ "$BACKUP_COUNT" -gt 3 ]; then
  ls -1d ./backups/mariadb_backup_* | head -n -3 | xargs rm -rf
  echo "✅ Removed old backups. Kept the most recent 3."
else
  echo "✅ Less than or equal to 3 backups found. No cleanup needed."
fi
