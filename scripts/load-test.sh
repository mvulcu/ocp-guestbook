#!/usr/bin/env bash

FRONTEND_URL="https://frontend-mashav-dev.apps.rm2.thpm.p1.openshiftapps.com"
API_URL="$FRONTEND_URL/api/entries"

echo "=== Guestbook Load Test ==="
echo "Target: $API_URL"
echo ""

# Function for creating a record
create_entry() {
  local id=$1
  curl -s -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"LoadTest-$id\",\"message\":\"This is test message #$id from load testing\"}" \
    > /dev/null
}

# Function for reading all records (creates cache load)
read_entries() {
  curl -s "$API_URL" > /dev/null
}

echo "Phase 1: Creating 100 entries..."
for i in {1..100}; do
  create_entry $i
  if [ $((i % 10)) -eq 0 ]; then
    echo "  Created $i entries..."
  fi
done
echo "✓ Created 100 entries"
echo ""

echo "Phase 2: Cache warming - reading entries 50 times..."
for i in {1..50}; do
  read_entries
  if [ $((i % 10)) -eq 0 ]; then
    echo "  Performed $i reads..."
  fi
done
echo "✓ Cache warmed up"
echo ""

echo "Phase 3: High-frequency reads (stress test)..."
echo "  Reading entries 200 times rapidly..."
for i in {1..200}; do
  read_entries &
  if [ $((i % 50)) -eq 0 ]; then
    wait
    echo "  Completed $i concurrent reads..."
  fi
done
wait
echo "✓ Stress test completed"
echo ""

echo "Phase 4: Getting all entry IDs for cleanup..."
ENTRY_IDS=$(curl -s "$API_URL" | grep -o '"id":[0-9]*' | grep -o '[0-9]*' | tail -n 100)

echo "Phase 5: Deleting test entries..."
count=0
for id in $ENTRY_IDS; do
  curl -s -X DELETE "$API_URL/$id" > /dev/null
  count=$((count + 1))
  if [ $((count % 20)) -eq 0 ]; then
    echo "  Deleted $count entries..."
  fi
done
echo "✓ Deleted $count test entries"
echo ""

echo "=== Load Test Complete ==="
echo "Check Grafana dashboard to see the metrics!"
