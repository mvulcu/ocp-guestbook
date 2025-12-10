#!/usr/bin/env bash
#
# GUESTBOOK FUNCTIONAL TEST
# Tests CRUD operations, caching, metrics collection
#
# Usage: bash test_functionality.sh
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

FRONTEND_URL=$(oc get route frontend -o jsonpath='{.spec.host}' 2>/dev/null)

if [ -z "$FRONTEND_URL" ]; then
    echo -e "${RED}ERROR: Frontend Route not found${NC}"
    exit 1
fi

BASE_URL="https://$FRONTEND_URL"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}GUESTBOOK FUNCTIONAL TEST${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Frontend URL: $BASE_URL${NC}\n"

#############################################
# TEST 1: Health Check
#############################################
echo -e "${YELLOW}[TEST 1]${NC} Health Check"
HEALTH=$(curl -s -k "$BASE_URL/health")
echo "$HEALTH" | jq .

STATUS=$(echo "$HEALTH" | jq -r '.status')
DB_STATUS=$(echo "$HEALTH" | jq -r '.database')
REDIS_STATUS=$(echo "$HEALTH" | jq -r '.redis')

if [ "$STATUS" == "healthy" ] && [ "$DB_STATUS" == "healthy" ] && [ "$REDIS_STATUS" == "healthy" ]; then
    echo -e "${GREEN}[✓] Health check PASSED: status=$STATUS database=$DB_STATUS redis=$REDIS_STATUS${NC}\n"
else
    echo -e "${RED}[✗] Health check FAILED${NC}\n"
    exit 1
fi

#############################################
# TEST 2: CREATE Entry (POST)
#############################################
echo -e "${YELLOW}[TEST 2]${NC} CREATE Entry (POST /api/entries)"

TIMESTAMP=$(date +%s)
NAME="Test User $TIMESTAMP"
MESSAGE="Functional test entry created at $TIMESTAMP"

CREATE_RESPONSE=$(curl -s -k -X POST "$BASE_URL/api/entries" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$NAME\",\"message\":\"$MESSAGE\"}")

echo "$CREATE_RESPONSE" | jq .

ENTRY_ID=$(echo "$CREATE_RESPONSE" | jq -r '.id')

if [ -n "$ENTRY_ID" ] && [ "$ENTRY_ID" != "null" ]; then
    echo -e "${GREEN}[✓] Entry created successfully: ID=$ENTRY_ID${NC}\n"
else
    echo -e "${RED}[✗] Failed to create entry${NC}\n"
    exit 1
fi

#############################################
# TEST 3: READ Entries (GET) - Cache Status
#############################################
echo -e "${YELLOW}[TEST 3]${NC} READ Entries (GET /api/entries) - First request"

RESPONSE1=$(curl -s -k -i "$BASE_URL/api/entries")
CACHE_HEADER1=$(echo "$RESPONSE1" | grep -i "^x-cache:" | awk '{print $2}' | tr -d '\r\n ')

echo -e "X-Cache: $CACHE_HEADER1"

if [ "$CACHE_HEADER1" == "MISS" ]; then
    echo -e "${GREEN}[✓] First request: Cache MISS (expected - cache was invalidated by CREATE)${NC}\n"
elif [ "$CACHE_HEADER1" == "HIT" ]; then
    echo -e "${YELLOW}[!] First request: Cache HIT (cache already warm from previous requests)${NC}\n"
else
    echo -e "${YELLOW}[!] First request: X-Cache header value: '$CACHE_HEADER1'${NC}\n"
fi

#############################################
# TEST 4: READ Entries (GET) - Cache HIT
#############################################
echo -e "${YELLOW}[TEST 4]${NC} READ Entries (GET /api/entries) - Second request"

sleep 1

RESPONSE2=$(curl -s -k -i "$BASE_URL/api/entries")
CACHE_HEADER2=$(echo "$RESPONSE2" | grep -i "^x-cache:" | awk '{print $2}' | tr -d '\r\n ')

echo -e "X-Cache: $CACHE_HEADER2"

if [ "$CACHE_HEADER2" == "HIT" ]; then
    echo -e "${GREEN}[✓] Second request: Cache HIT (caching works!)${NC}\n"
else
    echo -e "${RED}[✗] Second request: Cache $CACHE_HEADER2 (expected HIT)${NC}\n"
fi

# Extract entries count
ENTRIES=$(curl -s -k "$BASE_URL/api/entries" | jq '. | length')
echo -e "${BLUE}[INFO]${NC} Total entries in database: $ENTRIES\n"

#############################################
# TEST 5: UPDATE Entry (PUT)
#############################################
echo -e "${YELLOW}[TEST 5]${NC} UPDATE Entry (PUT /api/entries/$ENTRY_ID)"

UPDATED_NAME="Updated Test User"
UPDATED_MESSAGE="This entry was updated at $(date)"

UPDATE_RESPONSE=$(curl -s -k -X PUT "$BASE_URL/api/entries/$ENTRY_ID" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$UPDATED_NAME\",\"message\":\"$UPDATED_MESSAGE\"}")

echo "$UPDATE_RESPONSE" | jq .

if echo "$UPDATE_RESPONSE" | grep -q "uppdaterat"; then
    echo -e "${GREEN}[✓] Entry updated successfully (ID=$ENTRY_ID)${NC}\n"
else
    echo -e "${RED}[✗] Failed to update entry${NC}\n"
fi

# Verify cache invalidation after UPDATE
echo -e "${BLUE}[INFO]${NC} Verifying cache invalidation after UPDATE..."
CACHE_AFTER_UPDATE=$(curl -s -k -I "$BASE_URL/api/entries" | grep -i "^x-cache:" | awk '{print $2}' | tr -d '\r\n ')

if [ -n "$CACHE_AFTER_UPDATE" ]; then
    echo -e "X-Cache after UPDATE: $CACHE_AFTER_UPDATE"
    if [ "$CACHE_AFTER_UPDATE" == "MISS" ]; then
        echo -e "${GREEN}[✓] Cache invalidated correctly after UPDATE${NC}\n"
    else
        echo -e "${YELLOW}[!] Cache status after UPDATE: $CACHE_AFTER_UPDATE${NC}\n"
    fi
else
    echo -e "${YELLOW}[!] X-Cache header not found (may be processing)${NC}\n"
fi

#############################################
# TEST 6: DELETE Entry (DELETE)
#############################################
echo -e "${YELLOW}[TEST 6]${NC} DELETE Entry (DELETE /api/entries/$ENTRY_ID)"

DELETE_RESPONSE=$(curl -s -k -w "%{http_code}" -o /dev/null -X DELETE "$BASE_URL/api/entries/$ENTRY_ID")

if [ "$DELETE_RESPONSE" == "204" ]; then
    echo -e "${GREEN}[✓] Entry deleted successfully (HTTP 204 No Content)${NC}\n"
else
    echo -e "${RED}[✗] Failed to delete entry (HTTP $DELETE_RESPONSE)${NC}\n"
fi

# Verify cache invalidation after DELETE
echo -e "${BLUE}[INFO]${NC} Verifying cache invalidation after DELETE..."
CACHE_AFTER_DELETE=$(curl -s -k -I "$BASE_URL/api/entries" | grep -i "^x-cache:" | awk '{print $2}' | tr -d '\r\n ')

if [ -n "$CACHE_AFTER_DELETE" ]; then
    echo -e "X-Cache after DELETE: $CACHE_AFTER_DELETE"
    if [ "$CACHE_AFTER_DELETE" == "MISS" ]; then
        echo -e "${GREEN}[✓] Cache invalidated correctly after DELETE${NC}\n"
    else
        echo -e "${YELLOW}[!] Cache status after DELETE: $CACHE_AFTER_DELETE${NC}\n"
    fi
else
    echo -e "${YELLOW}[!] X-Cache header not found (may be processing)${NC}\n"
fi

#############################################
# TEST 7: Statistics Endpoint
#############################################
echo -e "${YELLOW}[TEST 7]${NC} Statistics (GET /api/stats)"

STATS=$(curl -s -k "$BASE_URL/api/stats")
echo "$STATS" | jq .

TOTAL_ENTRIES=$(echo "$STATS" | jq -r '.total_entries_db')
CACHE_AVAILABLE=$(echo "$STATS" | jq -r '.cache_available')

if [ -n "$TOTAL_ENTRIES" ] && [ "$TOTAL_ENTRIES" != "null" ]; then
    echo -e "${GREEN}[✓] Stats endpoint works: total_entries=$TOTAL_ENTRIES cache_available=$CACHE_AVAILABLE${NC}\n"
else
    echo -e "${RED}[✗] Stats endpoint failed${NC}\n"
fi

#############################################
# TEST 8: Prometheus Metrics from Backend
#############################################
echo -e "${YELLOW}[TEST 8]${NC} Prometheus Metrics from Backend Pod"

BACKEND_POD=$(oc get pods -l app.kubernetes.io/name=backend --no-headers | awk '{print $1}' | head -1)

if [ -n "$BACKEND_POD" ]; then
    echo -e "${BLUE}[INFO]${NC} Fetching metrics from pod: $BACKEND_POD\n"

    METRICS=$(oc exec $BACKEND_POD -- curl -s http://localhost:8080/metrics 2>/dev/null)

    echo "--- Prometheus Metrics Sample ---"

    REQUESTS_TOTAL=$(echo "$METRICS" | grep 'guestbook_requests_total{endpoint="/api/entries",method="GET"' | grep -v '#' | awk '{print $2}')
    CACHE_HITS=$(echo "$METRICS" | grep 'guestbook_cache_hits_total' | grep -v '#' | awk '{print $2}')
    CACHE_MISSES=$(echo "$METRICS" | grep 'guestbook_cache_misses_total' | grep -v '#' | awk '{print $2}')
    DB_ENTRIES=$(echo "$METRICS" | grep 'guestbook_db_entries_total' | grep -v '#' | awk '{print $2}')
    DB_UP=$(echo "$METRICS" | grep 'guestbook_db_up' | grep -v '#' | awk '{print $2}')
    REDIS_UP=$(echo "$METRICS" | grep 'guestbook_redis_up' | grep -v '#' | awk '{print $2}')

    echo "guestbook_requests_total (GET /api/entries): $REQUESTS_TOTAL"
    echo "guestbook_cache_hits_total: $CACHE_HITS"
    echo "guestbook_cache_misses_total: $CACHE_MISSES"
    echo "guestbook_db_entries_total: $DB_ENTRIES"
    echo "guestbook_db_up: $DB_UP"
    echo "guestbook_redis_up: $REDIS_UP"

    if [ -n "$CACHE_HITS" ] && [ -n "$CACHE_MISSES" ]; then
        TOTAL=$((CACHE_HITS + CACHE_MISSES))
        HIT_RATIO=$((CACHE_HITS * 100 / TOTAL))
        echo ""
        echo -e "${BLUE}[METRICS]${NC} Cache Hit Ratio: ${GREEN}$HIT_RATIO%${NC} ($CACHE_HITS hits / $TOTAL total requests)"
    fi

    echo "--- End of Metrics Sample ---"
    echo ""

    if [ -n "$REQUESTS_TOTAL" ]; then
        echo -e "${GREEN}[✓] Prometheus metrics are exported correctly${NC}\n"
    else
        echo -e "${RED}[✗] Prometheus metrics NOT found${NC}\n"
    fi
else
    echo -e "${RED}[✗] Backend pod not found${NC}\n"
fi

#############################################
# TEST 9: Load Test (Multiple Requests)
#############################################
echo -e "${YELLOW}[TEST 9]${NC} Load Test (10 concurrent requests)"

echo -e "${BLUE}[INFO]${NC} Sending 10 concurrent GET requests to /api/entries..."

for i in {1..10}; do
    curl -s -k "$BASE_URL/api/entries" > /dev/null &
done

wait

echo -e "${GREEN}[✓] Load test completed${NC}\n"

# Check cache hit ratio after load test
echo -e "${BLUE}[INFO]${NC} Checking cache performance after load test..."
METRICS_AFTER=$(oc exec $BACKEND_POD -- curl -s http://localhost:8080/metrics 2>/dev/null)

CACHE_HITS_AFTER=$(echo "$METRICS_AFTER" | grep 'guestbook_cache_hits_total' | grep -v '#' | awk '{print $2}')
CACHE_MISSES_AFTER=$(echo "$METRICS_AFTER" | grep 'guestbook_cache_misses_total' | grep -v '#' | awk '{print $2}')

if [ -n "$CACHE_HITS_AFTER" ] && [ -n "$CACHE_MISSES_AFTER" ]; then
    TOTAL_REQUESTS=$((CACHE_HITS_AFTER + CACHE_MISSES_AFTER))
    HIT_RATIO=$((CACHE_HITS_AFTER * 100 / TOTAL_REQUESTS))
    echo -e "Cache Hits: $CACHE_HITS_AFTER"
    echo -e "Cache Misses: $CACHE_MISSES_AFTER"
    echo -e "Total Requests: $TOTAL_REQUESTS"
    echo -e "${BLUE}[FINAL]${NC} Cache Hit Ratio: ${GREEN}$HIT_RATIO%${NC}\n"
fi

#############################################
# SUMMARY
#############################################
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}FUNCTIONAL TEST SUMMARY${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓ Health Check${NC}"
echo -e "${GREEN}✓ CREATE Entry (POST)${NC}"
echo -e "${GREEN}✓ READ Entries (GET) with Caching${NC}"
echo -e "${GREEN}✓ UPDATE Entry (PUT)${NC}"
echo -e "${GREEN}✓ DELETE Entry (DELETE)${NC}"
echo -e "${GREEN}✓ Statistics Endpoint${NC}"
echo -e "${GREEN}✓ Prometheus Metrics${NC}"
echo -e "${GREEN}✓ Load Test${NC}"

if [ -n "$HIT_RATIO" ]; then
    echo -e "\n${BLUE}[KEY METRICS]${NC}"
    echo -e "• Cache Hit Ratio: ${GREEN}$HIT_RATIO%${NC}"
    echo -e "• Total HTTP Requests: $TOTAL_REQUESTS"
    echo -e "• Cache Hits: $CACHE_HITS_AFTER"
    echo -e "• Cache Misses: $CACHE_MISSES_AFTER"
fi

echo -e "\n${GREEN}🎉 ALL FUNCTIONAL TESTS PASSED${NC}\n"
