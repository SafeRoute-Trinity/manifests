# SafeRoute Manifests

Kubernetes manifests for deploying SafeRoute on Azure Kubernetes Service (AKS). Covers all microservices, the data layer (PostGIS, RabbitMQ, Redis), monitoring (Prometheus, Grafana, Alertmanager, Blackbox Exporter), TLS (cert-manager + Let's Encrypt), and the GitHub Actions CD pipeline.

---

## Repository Structure

```
manifests/
├── .github/workflows/
│   └── deploy.yml              # CD pipeline: auto-deploy on push to main
├── k8s/
│   ├── namespaces/             # Namespace definitions
│   ├── base/
│   │   └── networkpolicies.yml
│   ├── saferoute/              # Application namespace
│   │   ├── ingress.yml         # NGINX ingress (saferoutemap.duckdns.org, TLS)
│   │   ├── api-ingress.yml     # API sub-path routing rules
│   │   ├── hpa.yml             # Horizontal Pod Autoscalers
│   │   ├── pdb.yml             # Pod Disruption Budgets
│   │   ├── rabbitmq-ingress.yml
│   │   ├── rabbitmq-management-service.yml
│   │   ├── redis/
│   │   ├── user-management/    # deployment.yml, service.yml, configmap.yml
│   │   ├── notification-service/
│   │   ├── routing-service/
│   │   ├── safety-scoring/
│   │   ├── sos/
│   │   ├── feedback/
│   │   └── coordinator-service/
│   ├── data/                   # Stateful data layer
│   │   ├── postgresql/         # PostgreSQL StatefulSet + PVC
│   │   ├── postgis/            # PostGIS StatefulSet + PVC
│   │   └── rabbitmq/           # RabbitMQ StatefulSet + PVC + ingress
│   ├── monitoring/
│   │   ├── prometheus/         # Scrape config, alert rules, deployment
│   │   ├── grafana/            # Dashboards: QPS + service health
│   │   ├── alertmanager/
│   │   ├── blackbox-exporter/  # HTTP probing of /health endpoints
│   │   └── grafana-ingress.yml
│   ├── cert-manager/
│   │   ├── cluster-issuer.yml  # Let's Encrypt (staging + prod ClusterIssuers)
│   │   ├── duckdns-webhook.yml
│   │   └── setup-https.sh
│   └── secrets/
│       └── rabbitmq-secret.yml
└── azure-monitor/
```

---

## Namespaces

| Namespace    | Contents                                             |
| ------------ | ---------------------------------------------------- |
| `saferoute`  | All application microservices + Redis                |
| `data`       | PostgreSQL, PostGIS, RabbitMQ (StatefulSets + PVCs)  |
| `monitoring` | Prometheus, Grafana, Alertmanager, Blackbox Exporter |

---

## Live Endpoints

| Hostname                                   | Purpose                          |
| ------------------------------------------ | -------------------------------- |
| `https://saferoutemap.duckdns.org`         | Main API (TLS via Let's Encrypt) |
| `https://saferoutemap.duckdns.org/grafana` | Grafana dashboards               |
| `https://saferouterabbitmq.duckdns.org`    | RabbitMQ Management UI           |

---

## Cluster Topology

The AKS cluster is deployed across **two availability zones** within a single region, with services replicated across zones. Pod anti-affinity rules prefer spreading replicas across nodes to maximise zone separation.

---

## Prerequisites

- `kubectl` v1.28+
- `helm` >= 3 (used as package manager in the CD pipeline)
- `az` (Azure CLI) for AKS credentials
- `KUBECONFIG` GitHub Actions secret - base64-encoded AKS kubeconfig

---

## CD Pipeline

The GitHub Actions workflow (`.github/workflows/deploy.yml`) handles all deployments.

### Automatic deploy (push to `main`)

Any push modifying `k8s/**` or the workflow file triggers a full deploy:

```
1. Fetch latest Docker Hub image tags for all services
2. Update image references in deployment YAMLs
3. Verify images exist on Docker Hub
4. kubectl apply (namespaces -> base -> data -> services -> ingress)
   Helm is used as the package manager for bundling manifests
5. Wait for rollout status on each deployment
6. Commit updated image tags back to repo
```

### Manual single-service deploy

GitHub Actions → "Deploy to Kubernetes" → Run workflow → choose service:

```
all | user-management | notification-service | routing-service |
safety-scoring | sos | feedback
```

### Webhook / repository dispatch

The backend CI sends a `repository_dispatch` event (`deploy-service` type) with a service name payload. The manifests workflow picks this up and deploys only that service.

---

## Deploy from Scratch

### 1. Connect to the cluster

```bash
az aks get-credentials --resource-group <rg> --name <cluster>
kubectl cluster-info
kubectl get nodes
```

### 2. Create namespaces

```bash
kubectl apply -f k8s/namespaces/
```

### 3. Network policies

```bash
kubectl apply -f k8s/base/networkpolicies.yml
```

### 4. Data layer

```bash
kubectl apply -f k8s/data/postgresql/
kubectl apply -f k8s/data/postgis/

kubectl apply -f k8s/secrets/rabbitmq-secret.yml
kubectl apply -f k8s/data/rabbitmq/

kubectl rollout status statefulset/postgresql -n data --timeout=5m
kubectl rollout status statefulset/rabbitmq -n data --timeout=5m
```

### 5. Redis

```bash
kubectl apply -f k8s/saferoute/redis/
```

### 6. Application services

```bash
for svc in user-management notification-service routing-service safety-scoring sos feedback coordinator-service; do
  kubectl apply -f k8s/saferoute/${svc}/
  kubectl rollout status deployment/${svc} -n saferoute --timeout=5m
done
```

### 7. Ingress

```bash
kubectl apply -f k8s/saferoute/ingress.yml
kubectl apply -f k8s/saferoute/api-ingress.yml
kubectl apply -f k8s/saferoute/rabbitmq-ingress.yml
```

### 8. TLS (cert-manager)

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager \
  -n cert-manager --timeout=300s

# Update email in cluster-issuer.yml, then apply
kubectl apply -f k8s/cert-manager/cluster-issuer.yml
```

cert-manager uses HTTP-01 challenge via the NGINX Ingress. Certificates are issued automatically; check status with:

```bash
kubectl get certificates -A
kubectl describe certificate saferoutemap-duckdns-tls -n saferoute
```

### 9. Monitoring

```bash
kubectl apply -f k8s/monitoring/prometheus/
kubectl apply -f k8s/monitoring/alertmanager/
kubectl apply -f k8s/monitoring/grafana/
kubectl apply -f k8s/monitoring/blackbox-exporter/
kubectl apply -f k8s/monitoring/grafana-ingress.yml
```

### 10. HPA and PDB

```bash
kubectl apply -f k8s/saferoute/hpa.yml
kubectl apply -f k8s/saferoute/pdb.yml
```

---

## Resource Configuration

### Pod Resources (per service)

| Resource | Request | Limit |
| -------- | ------- | ----- |
| Memory   | 64Mi    | 256Mi |
| CPU      | 25m     | 200m  |

### Replicas and Autoscaling

| Service         | Min Replicas | Max Replicas | Scale on              |
| --------------- | ------------ | ------------ | --------------------- |
| user-management | 2            | 3            | CPU >70%, Memory >80% |
| routing-service | 2            | 3            | CPU >70%, Memory >80% |
| safety-scoring  | 2            | 3            | CPU >70%, Memory >80% |
| feedback        | 2            | 3            | CPU >70%, Memory >80% |
| sos             | 2            | 3            | CPU >70%, Memory >80% |
| coordinator     | 2            | 3            | CPU >70%, Memory >80% |
| notification    | 1            | 2            | CPU >70%, Memory >80% |

notification-service runs a single outbox worker - min replicas is 1 to avoid duplicate delivery.

### Rolling Updates

All deployments use `maxSurge=1, maxUnavailable=0` - zero-downtime rolling updates.

Pod anti-affinity is configured to prefer spreading replicas across nodes.

---

## Data Layer

### Application Database (`postgresql` StatefulSet)

- **Image:** `postgis/postgis:15-3.4-alpine`
- **Database:** `saferoute` (user: `saferoute`)
- **Port:** 5432 (internal)
- **Resources:** 256Mi–512Mi RAM, 100m–500m CPU
- **Persistence:** PVC-backed StatefulSet (50 GiB, `managed` StorageClass)
- **Sidecar:** `postgres-exporter` on port 9187 (Prometheus metrics)
- **Stores:** users, trusted contacts, preferences, safety weights, route cache, outbox, CAS state, audit log, feedback, emergency records
- **Access:** `kubectl port-forward -n data svc/postgresql 5432:5432`

### Spatial Database (`postgis` StatefulSet)

- **Image:** `postgis/postgis:15-3.4-alpine`
- **Database:** `saferoute_geo` (user: `saferoute`)
- **Port:** 5432 (internal), 5433 (local port-forward)
- **Resources:** 256Mi–512Mi RAM, 200m–500m CPU
- **Persistence:** PVC-backed StatefulSet
- **Sidecar:** `postgres-exporter` on port 9187 (Prometheus metrics)
- **Stores:** `ways` table — street segments with spatial geometries and pre-computed safety scores; ETL sync state
- **Used by:** safety-scoring service exclusively
- **Access:** `kubectl port-forward -n data svc/postgis 5433:5432`

### RabbitMQ

- **Image:** `rabbitmq:3.13-management-alpine`
- **Ports:** 5672 (AMQP), 15672 (Management UI), 15692 (Prometheus metrics)
- **Resources:** 256Mi–512Mi RAM, 10m–200m CPU
- **Persistence:** PVC-backed volume (10 GiB)
- **Queues:** `sos.notification`, `feedback.email`, `feedback.submit`

### Redis

- **Image:** `redis:7`
- **Port:** 6379
- **Resources:** 128Mi–256Mi RAM, 10m–100m CPU
- **Persistence:** PVC-backed
- **Used for:** session/auth token cache, rate limiting (100 req/60s global, 10 req/60s auth), route result cache, JWKS cache (1h TTL)

---

## Monitoring

| Component         | Details                                                                                                                               |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Prometheus        | Scrapes all pods in `saferoute` and `data` namespaces every 15s. Also scrapes PostgreSQL exporter on port 9187. 3-day TSDB retention. |
| Grafana           | Two dashboards: QPS overview, service health                                                                                          |
| Alertmanager      | Alert routing from Prometheus alert rules                                                                                             |
| Blackbox Exporter | HTTP_2XX probes against 6 service `/health` endpoints                                                                                 |

---

## Secrets

Create secrets before applying service deployments:

```bash
# RabbitMQ credentials
kubectl apply -f k8s/secrets/rabbitmq-secret.yml

# Service secrets (Auth0, DB, Twilio, etc.)
kubectl create secret generic saferoute-env \
  --from-literal=AUTH0_DOMAIN=saferouteapp.eu.auth0.com \
  --from-literal=AUTH0_AUDIENCE=https://saferoutemap.duckdns.org \
  --from-literal=TWILIO_ACCOUNT_SID=... \
  --from-literal=TWILIO_AUTH_TOKEN=... \
  -n saferoute
```

GitHub Actions `KUBECONFIG` secret - base64-encoded kubeconfig:

```bash
cat ~/.kube/config | base64 -w 0
# Paste output as KUBECONFIG secret in GitHub repo settings
```

---

## Immutable Resource Handling

The deploy pipeline handles Kubernetes immutable resource errors gracefully:

| Resource                | Behaviour                                                                                                    |
| ----------------------- | ------------------------------------------------------------------------------------------------------------ |
| `StorageClass`          | Skipped - AKS manages StorageClasses                                                                         |
| `PersistentVolumeClaim` | Skipped if PVC already exists                                                                                |
| `StatefulSet`           | Warning logged. To change immutable fields: delete StatefulSet (PVCs and data are preserved), then re-apply. |

---

## Useful Commands

```bash
# All pods
kubectl get pods -A

# Application services
kubectl get pods,services -n saferoute

# Data layer
kubectl get pods,pvc -n data

# Monitoring
kubectl get pods -n monitoring

# Service logs
kubectl logs -n saferoute deployment/routing-service --tail=100 -f

# Describe a failing pod
kubectl describe pod <pod-name> -n saferoute

# Check ingress
kubectl get ingress -n saferoute

# Check HPA
kubectl get hpa -n saferoute

# Force restart
kubectl rollout restart deployment/routing-service -n saferoute

# Check certificates
kubectl get certificates -A
```

---

## Troubleshooting

| Problem                     | Fix                                                                                         |
| --------------------------- | ------------------------------------------------------------------------------------------- |
| Pod stuck in `Pending`      | Check PVC: `kubectl get pvc -n saferoute`; check node capacity                              |
| `ImagePullBackOff`          | Verify Docker Hub image exists as `:latest`                                                 |
| StorageClass error          | Expected - pipeline skips these automatically                                               |
| StatefulSet immutable error | Delete StatefulSet, PVCs preserve data, re-apply                                            |
| Certificate not issued      | Check NGINX Ingress is accessible on port 80 for HTTP-01 challenge; check cert-manager logs |
| 502 Bad Gateway             | Pods not ready; check `kubectl get pods -n saferoute`                                       |
| RabbitMQ errors             | Check StatefulSet in `data` namespace; verify `rabbitmq-secret`                             |
