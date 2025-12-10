#!/bin/bash

CLUSTER_NAME="guestbook"

echo "🗑️  Destroying Kind cluster '$CLUSTER_NAME'..."
kind delete cluster --name "$CLUSTER_NAME"

echo "✅ Cluster destroyed. Environment cleaned up."
