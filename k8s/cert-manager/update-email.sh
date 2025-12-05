#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <your-email@example.com>"
    echo ""
    echo "This script updates the email address in the ClusterIssuer configuration"
    echo "and applies it to your Kubernetes cluster."
    exit 1
fi

EMAIL="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Updating email to: $EMAIL"

# Update email in cluster-issuer.yml
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/your-email@example.com/$EMAIL/g" "$SCRIPT_DIR/cluster-issuer.yml"
else
    # Linux
    sed -i "s/your-email@example.com/$EMAIL/g" "$SCRIPT_DIR/cluster-issuer.yml"
fi

echo "Applying updated ClusterIssuer..."
kubectl apply -f "$SCRIPT_DIR/cluster-issuer.yml"

echo ""
echo "Waiting for ClusterIssuer to be ready..."
sleep 5

kubectl get clusterissuer

echo ""
echo "✅ Email updated! Certificates should start provisioning automatically."

