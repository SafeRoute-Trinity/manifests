#!/bin/bash
set -e

echo "🔒 Setting up HTTPS with cert-manager and Let's Encrypt"
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Kubernetes cluster connected${NC}"

# Step 1: Install cert-manager if not already installed
echo ""
echo "Step 1: Checking cert-manager installation..."
if kubectl get namespace cert-manager &> /dev/null; then
    echo -e "${GREEN}✓ cert-manager namespace exists${NC}"
else
    echo "Installing cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
    
    echo "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s || {
        echo -e "${YELLOW}Warning: cert-manager pods may still be starting. Continuing...${NC}"
    }
    echo -e "${GREEN}✓ cert-manager installed${NC}"
fi

# Step 2: Check if email is set in ClusterIssuer
echo ""
echo "Step 2: Checking ClusterIssuer configuration..."
EMAIL=$(grep -A 1 "email:" cluster-issuer.yml | grep -v "email:" | tr -d ' ' | head -1)

if [[ "$EMAIL" == "your-email@example.com" ]] || [[ -z "$EMAIL" ]]; then
    echo -e "${YELLOW}⚠ Warning: Email address not configured in cluster-issuer.yml${NC}"
    echo "Please update the email address in k8s/cert-manager/cluster-issuer.yml"
    echo "This email is used for Let's Encrypt registration and expiration notices."
    read -p "Enter your email address (or press Enter to skip): " USER_EMAIL
    if [[ -n "$USER_EMAIL" ]]; then
        # Update email in cluster-issuer.yml
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sed -i '' "s/your-email@example.com/$USER_EMAIL/g" cluster-issuer.yml
        else
            # Linux
            sed -i "s/your-email@example.com/$USER_EMAIL/g" cluster-issuer.yml
        fi
        echo -e "${GREEN}✓ Email updated in cluster-issuer.yml${NC}"
    else
        echo -e "${YELLOW}⚠ Skipping email update. Please update manually before applying.${NC}"
    fi
fi

# Step 3: Apply ClusterIssuer
echo ""
echo "Step 3: Applying ClusterIssuer..."
kubectl apply -f cluster-issuer.yml
echo -e "${GREEN}✓ ClusterIssuer applied${NC}"

# Step 4: Apply updated ingress resources
echo ""
echo "Step 4: Applying updated ingress resources with TLS..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")"

kubectl apply -f "$K8S_DIR/saferoute/ingress.yml"
kubectl apply -f "$K8S_DIR/saferoute/api-ingress.yml"
kubectl apply -f "$K8S_DIR/monitoring/grafana-ingress.yml"
kubectl apply -f "$K8S_DIR/saferoute/rabbitmq-ingress.yml"

echo -e "${GREEN}✓ All ingress resources applied${NC}"

# Step 5: Monitor certificate provisioning
echo ""
echo "Step 5: Monitoring certificate provisioning..."
echo "Waiting for certificates to be issued (this may take 1-2 minutes)..."
echo ""

for i in {1..12}; do
    echo -n "."
    sleep 10
    
    # Check certificate status
    CERT_COUNT=$(kubectl get certificates -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$CERT_COUNT" -gt 0 ]]; then
        echo ""
        echo ""
        echo -e "${GREEN}Certificates found! Checking status...${NC}"
        kubectl get certificates -A
        break
    fi
done

echo ""
echo ""
echo "📋 Certificate Status:"
kubectl get certificates -A 2>/dev/null || echo "No certificates found yet"

echo ""
echo "📋 Certificate Requests:"
kubectl get certificaterequests -A 2>/dev/null || echo "No certificate requests found yet"

echo ""
echo -e "${GREEN}✅ HTTPS setup complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Monitor certificate provisioning: kubectl get certificates -A"
echo "2. Check certificate details: kubectl describe certificate <name> -n <namespace>"
echo "3. Test HTTPS: curl -I https://saferoutemap.duckdns.org/health/user-management"
echo ""
echo "Certificates will be automatically renewed by cert-manager before expiration."

