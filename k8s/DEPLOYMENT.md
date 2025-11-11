# SafeRoute Kubernetes Deployment Guide

This guide provides step-by-step instructions to deploy SafeRoute microservices on both **Minikube** (local development) and **AWS EKS** (production).

## Table of Contents
- [Prerequisites](#prerequisites)
- [Option 1: Minikube Deployment](#option-1-minikube-deployment)
- [Option 2: AWS EKS Deployment](#option-2-aws-eks-deployment)
- [Post-Deployment Steps](#post-deployment-steps)
- [Verification & Testing](#verification--testing)
- [Troubleshooting](#troubleshooting)

---

## Option 1: Minikube Deployment

### Step 1: Start Minikube
```bash
# Start Minikube with sufficient resources
minikube start --memory=8192 --cpus=4 --driver=docker

# Verify Minikube is running
minikube status

# Enable required addons
minikube addons enable ingress
minikube addons enable metrics-server
```

### Step 2: Create Namespaces
```bash
# Navigate to the k8s directory
cd saferoute/k8s

# Create all namespaces
kubectl apply -f namespaces/namespaces.yml

# Verify namespaces are created
kubectl get namespaces
```

### Step 3: Create Secrets
```bash
# Create PostgreSQL credentials
kubectl create secret generic postgresql-credentials \
  --from-literal=username=saferoute_user \
  --from-literal=password=$(openssl rand -base64 32) \
  -n data

# Create Redis credentials
kubectl create secret generic redis-credentials \
  --from-literal=password=$(openssl rand -base64 32) \
  -n data

# Create Auth0 credentials
# TODO: Replace with your actual Auth0 credentials
kubectl create secret generic auth0-credentials \
  --from-literal=client-id=YOUR_AUTH0_CLIENT_ID \
  --from-literal=client-secret=YOUR_AUTH0_CLIENT_SECRET \
  -n saferoute

# Verify secrets are created
kubectl get secrets -n data
kubectl get secrets -n saferoute
```

### Step 4: Deploy Data Layer (PostgreSQL & Redis)
```bash
# Deploy PostgreSQL ConfigMaps
kubectl apply -f data/postgresql/configmap.yml

# Deploy PostgreSQL StatefulSet and Service
kubectl apply -f data/postgresql/statefulset.yml
kubectl apply -f data/postgresql/service.yml

# Wait for PostgreSQL to be ready (this may take 2-3 minutes)
kubectl wait --for=condition=ready pod -l app=postgresql -n data --timeout=300s

# Deploy Redis StatefulSet and Service
kubectl apply -f data/redis/statefulset.yml
kubectl apply -f data/redis/service.yml

# Wait for Redis to be ready
kubectl wait --for=condition=ready pod -l app=redis -n data --timeout=300s

# Verify data layer is running
kubectl get pods -n data
kubectl get pvc -n data
```

### Step 5: Deploy SafeRoute Application Services
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

### Step 6: Deploy Ingress
```bash
# Deploy Ingress resource
kubectl apply -f saferoute/ingress.yml

# Get Ingress URL
minikube ip

# Add to /etc/hosts for local testing
echo "$(minikube ip) saferoute.local" | sudo tee -a /etc/hosts

# Test Ingress (wait 1-2 minutes for Ingress to be ready)
curl http://saferoute.local/api/users/health
```

### Step 7: Deploy Network Policies
```bash
# Apply network policies for security
kubectl apply -f base/networkpolicies.yml

# Verify network policies
kubectl get networkpolicies -n data
kubectl get networkpolicies -n saferoute
```

### Step 8: Deploy Monitoring Stack (Optional)
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

# Access Prometheus
minikube service prometheus -n monitoring

# Access Grafana (default: admin/admin)
minikube service grafana -n monitoring

# Verify monitoring is scraping metrics
kubectl get pods -n monitoring
```

### Step 9: Deploy Backup CronJob (Optional)
```bash
# Deploy PostgreSQL backup CronJob
kubectl apply -f data/postgresql/cronjob-backup.yml

# Verify CronJob is created
kubectl get cronjobs -n data
```

---

## Option 2: AWS EKS Deployment

### Step 1: Create EKS Cluster
```bash
# Create EKS cluster (takes 15-20 minutes)
# TODO: Change cluster name and region as needed
eksctl create cluster \
  --name saferoute-prod \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 3 \
  --nodes-min 2 \
  --nodes-max 5 \
  --managed

# Verify cluster is created
kubectl get nodes

# Update kubeconfig (if needed)
aws eks update-kubeconfig --name saferoute-prod --region us-east-1
```

### Step 2: Install EBS CSI Driver
```bash
# Create IAM policy for EBS CSI Driver
curl -o ebs-csi-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-ebs-csi-driver/master/docs/example-iam-policy.json

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam create-policy \
  --policy-name Amazon_EBS_CSI_Driver_Policy \
  --policy-document file://ebs-csi-policy.json

# Create IAM service account for EBS CSI Driver
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster saferoute-prod \
  --attach-policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/Amazon_EBS_CSI_Driver_Policy \
  --approve \
  --override-existing-serviceaccounts \
  --region us-east-1

# Install EBS CSI Driver
kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.25"

# Verify EBS CSI Driver is running
kubectl get pods -n kube-system | grep ebs-csi
```

### Step 3: Install AWS Load Balancer Controller
```bash
# Create IAM policy for AWS Load Balancer Controller
curl -o alb-iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.0/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://alb-iam-policy.json

# Create IAM service account
eksctl create iamserviceaccount \
  --cluster=saferoute-prod \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve \
  --region us-east-1

# Install AWS Load Balancer Controller using Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=saferoute-prod \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# Verify installation
kubectl get deployment -n kube-system aws-load-balancer-controller
```

### Step 4: Create Storage Class
```bash
# Navigate to k8s directory
cd saferoute/k8s

# Apply EBS StorageClass
kubectl apply -f base/storageclass.yml

# Verify StorageClass
kubectl get storageclass
```

### Step 5: Create Namespaces
```bash
# Create all namespaces
kubectl apply -f namespaces/namespaces.yml

# Verify namespaces
kubectl get namespaces
```

### Step 6: Create Secrets with AWS Secrets Manager (Recommended)
```bash
# Create secrets in AWS Secrets Manager
aws secretsmanager create-secret \
  --name saferoute/postgresql/username \
  --secret-string "saferoute_user" \
  --region us-east-1

aws secretsmanager create-secret \
  --name saferoute/postgresql/password \
  --secret-string "$(openssl rand -base64 32)" \
  --region us-east-1

aws secretsmanager create-secret \
  --name saferoute/redis/password \
  --secret-string "$(openssl rand -base64 32)" \
  --region us-east-1

# TODO: Add your actual Auth0 credentials
aws secretsmanager create-secret \
  --name saferoute/auth0/client-id \
  --secret-string "YOUR_AUTH0_CLIENT_ID" \
  --region us-east-1

aws secretsmanager create-secret \
  --name saferoute/auth0/client-secret \
  --secret-string "YOUR_AUTH0_CLIENT_SECRET" \
  --region us-east-1

# Alternative: Create secrets directly in Kubernetes (simpler but less secure)
kubectl create secret generic postgresql-credentials \
  --from-literal=username=saferoute_user \
  --from-literal=password=$(openssl rand -base64 32) \
  -n data

kubectl create secret generic redis-credentials \
  --from-literal=password=$(openssl rand -base64 32) \
  -n data

kubectl create secret generic auth0-credentials \
  --from-literal=client-id=YOUR_AUTH0_CLIENT_ID \
  --from-literal=client-secret=YOUR_AUTH0_CLIENT_SECRET \
  -n saferoute
```

### Step 7: Deploy Data Layer
```bash
# Deploy PostgreSQL
kubectl apply -f data/postgresql/configmap.yml
kubectl apply -f data/postgresql/statefulset.yml
kubectl apply -f data/postgresql/service.yml

# Wait for PostgreSQL (may take 3-5 minutes for EBS volume provisioning)
kubectl wait --for=condition=ready pod -l app=postgresql -n data --timeout=600s

# Deploy Redis
kubectl apply -f data/redis/statefulset.yml
kubectl apply -f data/redis/service.yml

# Wait for Redis
kubectl wait --for=condition=ready pod -l app=redis -n data --timeout=300s

# Verify data layer and check EBS volumes
kubectl get pods -n data
kubectl get pvc -n data
aws ec2 describe-volumes --filters "Name=tag:kubernetes.io/created-for/pvc/namespace,Values=data"
```

### Step 8: Deploy Application Services
```bash
# Deploy ConfigMaps
kubectl apply -f saferoute/user-management/configmap.yml
kubectl apply -f saferoute/routing-service/configmap.yml
kubectl apply -f saferoute/sos/configmap.yml
kubectl apply -f saferoute/safety-scoring/configmap.yml
kubectl apply -f saferoute/feedback/configmap.yml

# Deploy all services
kubectl apply -f saferoute/user-management/
kubectl apply -f saferoute/routing-service/
kubectl apply -f saferoute/sos/
kubectl apply -f saferoute/safety-scoring/
kubectl apply -f saferoute/feedback/

# Wait for all services
kubectl wait --for=condition=ready pod -l tier=backend -n saferoute --timeout=300s

# Verify
kubectl get pods -n saferoute
kubectl get services -n saferoute
```

### Step 9: Deploy Ingress with ALB
```bash
# Deploy Ingress (will automatically create AWS ALB)
kubectl apply -f saferoute/ingress.yml

# Wait for ALB to be provisioned (2-3 minutes)
kubectl get ingress -n saferoute -w

# Get ALB DNS name
kubectl get ingress saferoute-ingress -n saferoute -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# TODO: Configure your DNS to point to the ALB
# Example: Create a CNAME record in Route 53
# saferoute.yourdomain.com -> k8s-saferoute-xxxxx.us-east-1.elb.amazonaws.com
```

### Step 10: Deploy Network Policies
```bash
# Apply network policies
kubectl apply -f base/networkpolicies.yml

# Verify
kubectl get networkpolicies --all-namespaces
```

### Step 11: Setup S3 Backup for PostgreSQL
```bash
# Create S3 bucket for backups
# TODO: Change bucket name to be unique
aws s3 mb s3://saferoute-backups-${AWS_ACCOUNT_ID} --region us-east-1

# Create IAM policy for backups
cat > backup-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::saferoute-backups-${AWS_ACCOUNT_ID}",
        "arn:aws:s3:::saferoute-backups-${AWS_ACCOUNT_ID}/*"
      ]
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name SafeRouteBackupPolicy \
  --policy-document file://backup-policy.json

# Create service account with IAM role
eksctl create iamserviceaccount \
  --name postgresql-backup-sa \
  --namespace data \
  --cluster saferoute-prod \
  --attach-policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/SafeRouteBackupPolicy \
  --approve \
  --region us-east-1

# Deploy backup CronJob
kubectl apply -f data/postgresql/cronjob-backup.yml

# Verify
kubectl get cronjobs -n data
```

### Step 12: Deploy Monitoring Stack
```bash
# Deploy Prometheus
kubectl apply -f monitoring/prometheus/rbac.yml
kubectl apply -f monitoring/prometheus/configmap.yml
kubectl apply -f monitoring/prometheus/deployment.yml
kubectl apply -f monitoring/prometheus/service.yml

# Deploy Grafana
kubectl apply -f monitoring/grafana/deployment.yml
kubectl apply -f monitoring/grafana/service.yml

# Wait for monitoring stack
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=300s

# Access Prometheus (for EKS, use port-forward or LoadBalancer)
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &

# Access Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000 &

# Open in browser: http://localhost:3000 (admin/admin)
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
  redis-cli -h redis.data.svc.cluster.local -a $(kubectl get secret redis-credentials -n data -o jsonpath='{.data.password}' | base64 -d) PING
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
# For Minikube
export SAFEROUTE_HOST=saferoute.local

# For EKS
export SAFEROUTE_HOST=$(kubectl get ingress saferoute-ingress -n saferoute -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test endpoints
curl http://${SAFEROUTE_HOST}/api/users/health
curl http://${SAFEROUTE_HOST}/api/routing/health
curl http://${SAFEROUTE_HOST}/api/sos/health
curl http://${SAFEROUTE_HOST}/api/safety/health
curl http://${SAFEROUTE_HOST}/api/feedback/health
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

### EBS Volume Issues
```bash
# Check PVC status
kubectl get pvc -n data

# Describe PVC for events
kubectl describe pvc postgresql-data-postgresql-0 -n data

# Check StorageClass
kubectl get storageclass

# Check EBS CSI Driver
kubectl get pods -n kube-system | grep ebs-csi
```

### Ingress Not Working
```bash
# Check Ingress status
kubectl get ingress -n saferoute

# Describe Ingress for events
kubectl describe ingress saferoute-ingress -n saferoute

# For Minikube: Check Ingress addon
minikube addons list | grep ingress

# For EKS: Check ALB Controller
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl logs -n kube-system deployment/aws-load-balancer-controller
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
# For Minikube
minikube delete

# For EKS (CAUTION: This deletes everything!)
# Delete all resources first
kubectl delete namespace saferoute
kubectl delete namespace data
kubectl delete namespace monitoring

# Delete EKS cluster
eksctl delete cluster --name saferoute-prod --region us-east-1
```

---

## Cost Optimization Tips

### EKS Cost Savings
```bash
# Use spot instances for non-critical workloads
eksctl create nodegroup \
  --cluster saferoute-prod \
  --region us-east-1 \
  --name spot-workers \
  --node-type t3.medium \
  --nodes 2 \
  --spot

# Scale down during off-hours
kubectl scale deployment --all --replicas=1 -n saferoute

# Use Horizontal Pod Autoscaler
kubectl autoscale deployment user-management -n saferoute --cpu-percent=70 --min=2 --max=10
```

### Monitor Costs
```bash
# Check EBS volumes
kubectl get pvc --all-namespaces

# Check LoadBalancers
kubectl get svc --all-namespaces | grep LoadBalancer

# Review AWS Cost Explorer for detailed breakdown
```

---

## Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Minikube Documentation](https://minikube.sigs.k8s.io/docs/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)

---

## Support

For issues or questions:
1. Check pod logs: `kubectl logs <pod-name> -n <namespace>`
2. Check pod events: `kubectl describe pod <pod-name> -n <namespace>`
3. Review this troubleshooting guide
4. Check application-specific logs and metrics in Grafana

