#!/usr/bin/env bash

FRONTEND_URL="https://frontend-mashav-dev.apps.rm2.thpm.p1.openshiftapps.com"
API_URL="$FRONTEND_URL/api/entries"

echo "=== STRESS TEST ==="
echo "This will generate massive load!"
echo ""

# Создание большого количества записей быстро
echo "Creating 500 entries in parallel..."
for i in {1..500}; do
  (
    curl -s -X POST "$API_URL" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"Stress-$i\",\"message\":\"Stress test message $i\"}" \
      > /dev/null
  ) &

  # Ограничиваем параллельность до 50 одновременных запросов
  if [ $((i % 50)) -eq 0 ]; then
    wait
    echo "  Created $i entries..."
  fi
done
wait
echo "✓ 500 entries created"
echo ""

echo "Cache invalidation storm - rapid creates, updates, deletes..."
for i in {1..50}; do
  # Create
  curl -s -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"Storm-$i\",\"message\":\"Storm $i\"}" \
    > /dev/null &

  # Read (parallel)
  curl -s "$API_URL" > /dev/null &

  if [ $((i % 10)) -eq 0 ]; then
    wait
    echo "  Completed $i operations..."
  fi
done
wait
echo "✓ Cache storm completed"
echo ""

echo "Massive concurrent reads..."
for i in {1..1000}; do
  curl -s "$API_URL" > /dev/null &
  if [ $((i % 100)) -eq 0 ]; then
    wait
    echo "  Completed $i reads..."
  fi
done
wait
echo "✓ 1000 concurrent reads completed"
echo ""

echo "=== STRESS TEST COMPLETE ==="
echo ""
echo "NOW CHECK YOUR GRAFANA DASHBOARD!"
echo "You should see:"
echo "  - Cache Hit Ratio spike"
echo "  - Request rate increase"
echo "  - Latency changes"
echo "  - Cache invalidations"
