# SafeRoute Kubernetes Deployment Guide

This guide provides step-by-step instructions to deploy SafeRoute microservices on **Azure Kubernetes Service (AKS)**.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Azure AKS Deployment](#azure-aks-deployment)
- [Post-Deployment Steps](#post-deployment-steps)
- [Verification & Testing](#verification--testing)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before deploying, ensure you have:
- Azure CLI installed and configured (`az login`)
- `kubectl` installed
- `helm` installed (for some optional components)
- An Azure subscription with appropriate permissions
- Azure Container Registry (ACR) access (if using private images)

---

## Azure AKS Deployment

### Step 1: Create AKS Cluster
```bash
# Set variables (adjust as needed)
RESOURCE_GROUP="saferoute-rg"
AKS_CLUSTER_NAME="saferoute-aks"
LOCATION="eastus"
NODE_COUNT=3
NODE_VM_SIZE="Standard_D2s_v3"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create AKS cluster (takes 10-15 minutes)
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --node-count $NODE_COUNT \
  --node-vm-size $NODE_VM_SIZE \
  --enable-managed-identity \
  --enable-azure-rbac \
  --enable-addons monitoring \
  --generate-ssh-keys

# Get AKS credentials
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME

# Verify cluster is accessible
kubectl get nodes
```

### Step 2: Install NGINX Ingress Controller (Optional but Recommended)
```bash
# Add NGINX Ingress Helm repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install NGINX Ingress Controller
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz

# Wait for LoadBalancer IP to be assigned
kubectl get service ingress-nginx-controller -n ingress-nginx -w

# Get the external IP
kubectl get service ingress-nginx-controller -n ingress-nginx
```

### Step 3: Verify Storage Classes (Optional)
```bash
# AKS comes with default storage classes pre-configured
# Check available storage classes
kubectl get storageclass

# AKS typically provides:
# - managed-premium: Premium SSD (Premium_LRS) - recommended for databases
# - default or managed-csi: Standard SSD (Standard_LRS)

# Note: If you need custom settings (ReadOnly caching, Retain policy, etc.),
# you can create a custom storage class using base/storageclass.yml
```

### Step 4: Create Namespaces
```bash
# Navigate to the k8s directory
cd saferoute/k8s

# Create all namespaces
kubectl apply -f namespaces/namespaces.yml

# Verify namespaces are created
kubectl get namespaces
```

### Step 5: Create Secrets
```bash
# Create PostgreSQL credentials (note: secret name must match deployment references)
kubectl create secret generic postgresql-secret \
  --from-literal=username=saferoute_user \
  --from-literal=password=$(openssl rand -base64 32) \
  -n data

# Create Redis credentials
kubectl create secret generic redis-secret \
  --from-literal=password=$(openssl rand -base64 32) \
  -n data

# Create Auth0 credentials
# TODO: Replace with your actual Auth0 credentials
kubectl create secret generic auth0-secret \
  --from-literal=client-id=YOUR_AUTH0_CLIENT_ID \
  --from-literal=client-secret=YOUR_AUTH0_CLIENT_SECRET \
  -n saferoute

# Verify secrets are created
kubectl get secrets -n data
kubectl get secrets -n saferoute
```

### Step 6: Deploy Data Layer (PostgreSQL & Redis)
```bash
# Deploy PostgreSQL ConfigMaps
kubectl apply -f data/postgresql/configmap.yml

# Deploy PostgreSQL PVC (for Deployment)
kubectl apply -f data/postgresql/pvc.yml

# Deploy PostgreSQL Deployment and Service
kubectl apply -f data/postgresql/deployment.yml
kubectl apply -f data/postgresql/service.yml

# Wait for PostgreSQL to be ready (may take 3-5 minutes for Azure Disk provisioning)
kubectl wait --for=condition=ready pod -l app=postgresql -n data --timeout=600s

# Deploy Redis PVC (for Deployment)
kubectl apply -f data/redis/pvc.yml

# Deploy Redis Deployment and Service
kubectl apply -f data/redis/deployment.yml
kubectl apply -f data/redis/service.yml

# Wait for Redis to be ready
kubectl wait --for=condition=ready pod -l app=redis -n data --timeout=300s

# Verify data layer is running
kubectl get pods -n data
kubectl get pvc -n data
```

### Step 7: Deploy SafeRoute Application Services
```bash
# Deploy ConfigMaps for all services
kubectl apply -f saferoute/user-management/configmap.yml
kubectl apply -f saferoute/routing-service/configmap.yml
kubectl apply -f saferoute/sos/configmap.yml
kubectl apply -f saferoute/safety-scoring/configmap.yml
kubectl apply -f saferoute/feedback/configmap.yml

# Deploy User Management Service
kubectl apply -f saferoute/user-management/deployment.yml
kubectl apply -f saferoute/user-management/service.yml

# Deploy Routing Service
kubectl apply -f saferoute/routing-service/deployment.yml
kubectl apply -f saferoute/routing-service/service.yml

# Deploy SOS Service
kubectl apply -f saferoute/sos/deployment.yml
kubectl apply -f saferoute/sos/service.yml

# Deploy Safety Scoring Service
kubectl apply -f saferoute/safety-scoring/deployment.yml
kubectl apply -f saferoute/safety-scoring/service.yml

# Deploy Feedback Service
kubectl apply -f saferoute/feedback/deployment.yml
kubectl apply -f saferoute/feedback/service.yml

# Wait for all services to be ready
kubectl wait --for=condition=ready pod -l tier=backend -n saferoute --timeout=300s

# Verify all services are running
kubectl get pods -n saferoute
kubectl get services -n saferoute
```

### Step 8: Deploy Ingress
```bash
# Deploy Ingress resource
kubectl apply -f saferoute/ingress.yml

# Wait for Ingress to be ready (1-2 minutes)
kubectl get ingress -n saferoute -w

# Get the external IP from NGINX Ingress Controller
INGRESS_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Get the hostname from Ingress
INGRESS_HOST=$(kubectl get ingress saferoute-ingress -n saferoute -o jsonpath='{.spec.rules[0].host}')

echo "Ingress IP: $INGRESS_IP"
echo "Ingress Host: $INGRESS_HOST"

# TODO: Configure your DNS to point to the LoadBalancer IP
# Example: Create an A record in your DNS provider
# saferoute.yourdomain.com -> $INGRESS_IP

# Test Ingress (replace with your actual domain or use the IP)
curl -H "Host: saferoute.local" http://$INGRESS_IP/api/users/health
```

### Step 9: Deploy Network Policies
```bash
# Apply network policies for security
kubectl apply -f base/networkpolicies.yml

# Verify network policies
kubectl get networkpolicies -n data
kubectl get networkpolicies -n saferoute
```

### Step 10: Deploy Monitoring Stack (Optional)
```bash
# Create RBAC for Prometheus
kubectl apply -f monitoring/prometheus/rbac.yml

# Deploy Prometheus ConfigMap
kubectl apply -f monitoring/prometheus/configmap.yml

# Deploy Prometheus
kubectl apply -f monitoring/prometheus/deployment.yml
kubectl apply -f monitoring/prometheus/service.yml

# Deploy Grafana
kubectl apply -f monitoring/grafana/deployment.yml
kubectl apply -f monitoring/grafana/service.yml

# Wait for monitoring stack to be ready
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=300s

# Access Prometheus via port-forward
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &

# Access Grafana via port-forward (default: admin/admin)
kubectl port-forward -n monitoring svc/grafana 3000:3000 &

# Open in browser: http://localhost:3000

# Verify monitoring is scraping metrics
kubectl get pods -n monitoring
```

### Step 11: Setup Azure Blob Storage Backup for PostgreSQL (Optional)
```bash
# Set variables
STORAGE_ACCOUNT_NAME="saferoutebackups$(openssl rand -hex 4)"
CONTAINER_NAME="postgresql-backups"
RESOURCE_GROUP="saferoute-rg"
LOCATION="eastus"

# Create storage account
az storage account create \
  --name $STORAGE_ACCOUNT_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS

# Create container
az storage container create \
  --name $CONTAINER_NAME \
  --account-name $STORAGE_ACCOUNT_NAME \
  --auth-mode login

# Get storage account key
STORAGE_KEY=$(az storage account keys list \
  --resource-group $RESOURCE_GROUP \
  --account-name $STORAGE_ACCOUNT_NAME \
  --query "[0].value" -o tsv)

# Create Kubernetes secret for storage account
kubectl create secret generic azure-storage-credentials \
  --from-literal=account-name=$STORAGE_ACCOUNT_NAME \
  --from-literal=account-key=$STORAGE_KEY \
  --from-literal=container-name=$CONTAINER_NAME \
  -n data

# Update cronjob-backup.yml to use Azure Blob Storage
# TODO: Modify data/postgresql/cronjob-backup.yml to use Azure CLI or azcopy

# Deploy PostgreSQL backup CronJob
kubectl apply -f data/postgresql/cronjob-backup.yml

# Verify CronJob is created
kubectl get cronjobs -n data
```

---

## Post-Deployment Steps

### Configure Grafana Dashboards
```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Open browser: http://localhost:3000
# Login: admin/admin
# Add Prometheus data source:
# - URL: http://prometheus.monitoring.svc.cluster.local:9090
# - Save & Test
# Import dashboard ID: 6417 (Kubernetes Cluster Monitoring)
```

### Test Database Connectivity
```bash
# Test PostgreSQL connection
kubectl run -it --rm psql-test --image=postgres:15-alpine --restart=Never -n data -- \
  psql -h postgresql.data.svc.cluster.local -U saferoute_user -d saferoute -c "SELECT version();"

# Test Redis connection
kubectl run -it --rm redis-test --image=redis:7-alpine --restart=Never -n data -- \
  redis-cli -h redis.data.svc.cluster.local -a $(kubectl get secret redis-secret -n data -o jsonpath='{.data.password}' | base64 -d) PING
```

### Scale Services
```bash
# Scale up user-management service
kubectl scale deployment user-management -n saferoute --replicas=5

# Scale down for cost savings
kubectl scale deployment feedback -n saferoute --replicas=1

# Check status
kubectl get deployments -n saferoute
```

---

## Verification & Testing

### Check All Pods
```bash
# Check all pods across namespaces
kubectl get pods --all-namespaces

# Check specific namespace
kubectl get pods -n saferoute
kubectl get pods -n data
kubectl get pods -n monitoring
```

### Check Services
```bash
# Check all services
kubectl get services --all-namespaces

# Test service connectivity from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://user-management.saferoute.svc.cluster.local/health
```

### Check Logs
```bash
# View logs for a specific pod
kubectl logs -f <pod-name> -n saferoute

# View logs for all pods in a deployment
kubectl logs -f deployment/user-management -n saferoute

# View PostgreSQL logs
kubectl logs -f postgresql-0 -n data -c postgresql
```

### Check Resource Usage
```bash
# Check node resources
kubectl top nodes

# Check pod resources
kubectl top pods -n saferoute
kubectl top pods -n data
```

### Test API Endpoints
```bash
# Get the Ingress IP
INGRESS_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
INGRESS_HOST=$(kubectl get ingress saferoute-ingress -n saferoute -o jsonpath='{.spec.rules[0].host}')

# Test endpoints (using Host header or actual domain)
curl -H "Host: $INGRESS_HOST" http://$INGRESS_IP/api/users/health
curl -H "Host: $INGRESS_HOST" http://$INGRESS_IP/api/routing/health
curl -H "Host: $INGRESS_HOST" http://$INGRESS_IP/api/sos/health
curl -H "Host: $INGRESS_HOST" http://$INGRESS_IP/api/safety/health
curl -H "Host: $INGRESS_HOST" http://$INGRESS_IP/api/feedback/health

# Or if DNS is configured:
# curl https://saferoute.yourdomain.com/api/users/health
```

---

## Troubleshooting

### Pod Not Starting
```bash
# Describe pod to see events
kubectl describe pod <pod-name> -n saferoute

# Check logs
kubectl logs <pod-name> -n saferoute

# Check previous logs if pod restarted
kubectl logs <pod-name> -n saferoute --previous
```

### Database Connection Issues
```bash
# Check PostgreSQL is running
kubectl get pods -n data -l app=postgresql

# Check service endpoints
kubectl get endpoints -n data

# Test connection from a pod
kubectl run -it --rm debug --image=postgres:15-alpine --restart=Never -n data -- \
  psql -h postgresql.data.svc.cluster.local -U saferoute_user -d saferoute
```

### Azure Disk Volume Issues
```bash
# Check PVC status
kubectl get pvc -n data

# Describe PVC for events
kubectl describe pvc postgresql-data -n data
kubectl describe pvc redis-data -n data

# Check StorageClass
kubectl get storageclass

# Check Azure Disk CSI Driver (should be running by default in AKS)
kubectl get pods -n kube-system | grep csi-azuredisk

# Check Azure Disk CSI Driver logs if issues
kubectl logs -n kube-system -l app=csi-azuredisk-controller

# List Azure Disks in resource group
az disk list --resource-group $RESOURCE_GROUP --query "[].{Name:name,Size:diskSizeGb,State:diskState}" -o table
```

### Ingress Not Working
```bash
# Check Ingress status
kubectl get ingress -n saferoute

# Describe Ingress for events
kubectl describe ingress saferoute-ingress -n saferoute

# Check NGINX Ingress Controller
kubectl get pods -n ingress-nginx
kubectl get service ingress-nginx-controller -n ingress-nginx

# Check NGINX Ingress Controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller

# Verify LoadBalancer has external IP
kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Network Policy Issues
```bash
# Temporarily disable network policies for testing
kubectl delete networkpolicy --all -n data
kubectl delete networkpolicy --all -n saferoute

# Re-apply after testing
kubectl apply -f base/networkpolicies.yml
```

### Clean Up Everything
```bash
# CAUTION: This deletes everything!

# Delete all resources first
kubectl delete namespace saferoute
kubectl delete namespace data
kubectl delete namespace monitoring
kubectl delete namespace ingress-nginx

# Delete AKS cluster and resource group
az aks delete --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --yes

# Delete resource group (this will delete all resources including storage accounts)
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

---

## Cost Optimization Tips

### AKS Cost Savings
```bash
# Use Spot node pools for non-critical workloads
az aks nodepool add \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $AKS_CLUSTER_NAME \
  --name spotpool \
  --node-count 2 \
  --node-vm-size Standard_D2s_v3 \
  --priority Spot \
  --eviction-policy Delete \
  --spot-max-price -1 \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 5

# Scale down during off-hours
kubectl scale deployment --all --replicas=1 -n saferoute

# Scale down node pool
az aks scale \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --node-count 1 \
  --nodepool-name nodepool1

# Use Horizontal Pod Autoscaler
kubectl autoscale deployment user-management -n saferoute --cpu-percent=70 --min=2 --max=10

# Enable cluster autoscaler (if not already enabled)
az aks update \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 5
```

### Monitor Costs
```bash
# Check Azure Disk volumes
kubectl get pvc --all-namespaces

# Check LoadBalancers
kubectl get svc --all-namespaces | grep LoadBalancer

# List Azure Disks and their sizes
az disk list --resource-group $RESOURCE_GROUP --query "[].{Name:name,Size:diskSizeGb,Type:sku.name}" -o table

# Review Azure Cost Management for detailed breakdown
# Visit: https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/overview
```

---

## Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Azure Kubernetes Service (AKS) Documentation](https://docs.microsoft.com/azure/aks/)
- [AKS Best Practices](https://docs.microsoft.com/azure/aks/best-practices)
- [Azure Disk CSI Driver](https://github.com/kubernetes-sigs/azuredisk-csi-driver)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)

---

## Support

For issues or questions:
1. Check pod logs: `kubectl logs <pod-name> -n <namespace>`
2. Check pod events: `kubectl describe pod <pod-name> -n <namespace>`
3. Review this troubleshooting guide
4. Check application-specific logs and metrics in Grafana

