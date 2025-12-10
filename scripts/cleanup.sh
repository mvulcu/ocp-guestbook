#!/usr/bin/env bash

FRONTEND_URL="https://frontend-mashav-dev.apps.rm2.thpm.p1.openshiftapps.com"
API_URL="$FRONTEND_URL/api/entries"

echo "=== Cleaning up test data ==="

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo "ERROR: jq not found. Install it with: sudo apt install jq"
  echo "Falling back to manual deletion..."
  echo ""
  echo "Delete test entries manually through the web UI:"
  echo "  $FRONTEND_URL"
  exit 1
fi

# Get all records
ENTRIES=$(curl -s "$API_URL")

# Parsing with jq and removing test data
count=0
echo "$ENTRIES" | jq -r '.[] | select(.name | test("^(LoadTest-|Stress-|Storm-)")) | "\(.id) \(.name)"' | while read id name; do
  echo "  Deleting: $name (ID: $id)"
  curl -s -X DELETE "$API_URL/$id" > /dev/null
  count=$((count + 1))
done

echo ""
echo "✓ Cleanup complete"
echo "Check the frontend to verify: $FRONTEND_URL"
