#!/bin/bash

API_URL="https://guestbook.cicd.cachefly.site/api/entries"

echo "🚀 Populating Guestbook with dummy data..."

post_entry() {
    local name="$1"
    local message="$2"
    echo "📝 Posting: $name says '$message'"
    curl -s -X POST "$API_URL" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"$name\",\"message\":\"$message\"}"
    echo ""
}

post_entry "Alice" "Just managed to deploy this on Kubernetes!"
post_entry "Bob" "Greetings from the VPS terminal."
post_entry "Charlie" "The new UI looks amazing using the dark theme."
post_entry "DevOps_Bot" "Automated test entry #42. Systems functional."
post_entry "Eve" "Testing the persistence layer. hope this stays!"
post_entry "Frank" "Why use OpenShift when you have Kind?"
post_entry "Grace" "CI/CD pipeline is finally green. Time for coffee."
post_entry "Heidi" "Did anyone check the Redis cache hit ratio?"
post_entry "Ivan" "Scaling up to 10 replicas just for fun."
post_entry "Judy" "Hello World! This guestbook is alive."

echo "✅ Done! Refresh the page."
