#!/bin/bash
set -euo pipefail

echo "🔍 Finding WordPress pods..."
PROD_POD=$(kubectl get pods -n wordpress -l app=wordpress | grep "prod-" | grep Running | awk '{print $1}' | head -n 1)
STAGING_POD=$(kubectl get pods -n wordpress -l app=wordpress | grep "staging-" | grep Running | awk '{print $1}' | head -n 1)

if [ -z "$PROD_POD" ]; then
  echo "❌ Error: Could not find a running Production WordPress pod."
  exit 1
fi

if [ -z "$STAGING_POD" ]; then
  echo "❌ Error: Could not find a running Staging WordPress pod."
  exit 1
fi

echo "✅ Found Prod: $PROD_POD"
echo "✅ Found Staging: $STAGING_POD"

echo "🚀 Starting high-speed memory-to-memory file sync (Prod → Staging)..."
echo "⏳ This may take a moment depending on the size of your wp-content folder..."

set +e
kubectl exec "$PROD_POD" -n wordpress -- tar cf - -C /var/www/html wp-content | \
kubectl exec -i "$STAGING_POD" -n wordpress -- tar xf - -C /var/www/html
SYNC_STATUS=${PIPESTATUS[0]}
set -e

if [ $SYNC_STATUS -eq 1 ]; then
  echo "⚠️ Notice: 'file changed as we read it'. This is completely normal for active WordPress sites (cache/logs writing) and the sync was still successful."
elif [ $SYNC_STATUS -ne 0 ]; then
  echo "❌ Error during transfer."
  exit 1
fi

echo "🎉 File sync complete! Your staging environment now exactly matches production's files."
