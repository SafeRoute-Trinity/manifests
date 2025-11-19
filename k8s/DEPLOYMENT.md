# SafeRoute Kubernetes Deployment Guide

Complete guide for deploying SafeRoute via GitHub Actions.

## Architecture Overview

SafeRoute consists of:

### Microservices
- **user-management**: User authentication and profile management
- **notification-service**: Push notifications and alerts
- **routing-service**: Route calculation and optimization
- **safety-scoring**: Safety metrics and scoring algorithms
- **sos**: Emergency SOS handling
- **feedback**: User feedback collection

### Infrastructure
- **PostgreSQL**: Primary database (StatefulSet)
- **Redis**: Caching and session storage (StatefulSet)
- **RabbitMQ**: Message queue for async processing (StatefulSet)
- **Prometheus**: Metrics collection and monitoring
- **Grafana**: Metrics visualization

## Deployment via GitHub Actions

All deployments are handled through GitHub Actions workflows.

### Manual Deployment

1. Go to the **Actions** tab in GitHub
2. Select **Deploy to Kubernetes** workflow
3. Click **Run workflow**
4. Fill in parameters:
   - **Service**: Choose specific service or "all"
   - **Image Tag**: Docker image tag (e.g., `v1.0.0`, `latest`)
   - **Environment**: `staging` or `production`
5. Click **Run workflow**

### Automated Deployment (Webhook)

Service repositories can trigger deployments via API:

```bash
curl -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  https://api.github.com/repos/YOUR_ORG/saferoute-manifest/dispatches \
  -d '{
    "event_type": "deploy-service",
    "client_payload": {
      "service": "user-management",
      "image_tag": "v1.2.3",
      "environment": "production"
    }
  }'
```

## Docker Images

All services use images from Docker Hub:

| Service | Docker Hub Repository | Default Tag |
|---------|----------------------|-------------|
| user-management | saferoute/user-management | latest |
| notification-service | saferoute/notification | latest |
| routing-service | saferoute/routing-service | latest |
| safety-scoring | saferoute/safety-scoring | latest |
| sos | saferoute/sos | latest |
| feedback | saferoute/feedback | latest |

Images are built in their service repositories and pushed to Docker Hub.

## Configuration

### Required Secrets

Create these Kubernetes secrets before deploying:

#### PostgreSQL Secret
```bash
kubectl create secret generic postgresql-secret \
  --from-literal=username=postgres \
  --from-literal=password=YOUR_PASSWORD \
  -n data
```

#### Redis Secret
```bash
kubectl create secret generic redis-secret \
  --from-literal=password=YOUR_REDIS_PASSWORD \
  -n data
```

#### RabbitMQ Secret
```bash
kubectl create secret generic rabbitmq-secret \
  --from-literal=username=admin \
  --from-literal=password=YOUR_RABBITMQ_PASSWORD \
  --from-literal=erlang-cookie=YOUR_ERLANG_COOKIE \
  -n saferoute
```

#### Auth0 Secret (for user-management)
```bash
kubectl create secret generic auth0-secret \
  --from-literal=client-id=YOUR_AUTH0_CLIENT_ID \
  --from-literal=client-secret=YOUR_AUTH0_CLIENT_SECRET \
  -n saferoute
```

### ConfigMaps

Each service has its own ConfigMap:
- `k8s/saferoute/*/configmap.yml`

Review and update before deployment.

## Monitoring Deployments

### Check Status via kubectl

```bash
# Get all pods
kubectl get pods -n saferoute

# Get all services
kubectl get services -n saferoute

# Check specific deployment
kubectl describe deployment user-management -n saferoute

# View logs
kubectl logs -f deployment/user-management -n saferoute

# Check rollout status
kubectl rollout status deployment/user-management -n saferoute
```

### Check in GitHub Actions

1. Go to Actions tab
2. Click on deployment workflow run
3. Review deployment summary
4. Check step-by-step logs

## Rollback

### Via GitHub Actions

1. Go to Actions → Deploy to Kubernetes
2. Enter previous stable tag
3. Run workflow with same service and environment

### Via kubectl (Emergency)

```bash
# View rollout history
kubectl rollout history deployment/user-management -n saferoute

# Rollback to previous version
kubectl rollout undo deployment/user-management -n saferoute

# Rollback to specific revision
kubectl rollout undo deployment/user-management --to-revision=2 -n saferoute
```

## Namespaces

- `saferoute`: Application microservices
- `data`: PostgreSQL and Redis
- `monitoring`: Prometheus and Grafana

## Ingress Configuration

Configure routing in `k8s/saferoute/ingress.yml`:
- `/api/users/*` → user-management
- `/api/routes/*` → routing-service
- `/api/safety/*` → safety-scoring
- `/api/sos/*` → sos
- `/api/feedback/*` → feedback
- `/api/notifications/*` → notification-service

## Scaling

### Horizontal Pod Autoscaling

```bash
kubectl autoscale deployment user-management \
  --cpu-percent=70 \
  --min=1 \
  --max=10 \
  -n saferoute
```

### Manual Scaling

```bash
kubectl scale deployment user-management --replicas=3 -n saferoute
```

## Troubleshooting

### Deployment Failed in GitHub Actions

1. Check workflow logs in Actions tab
2. Common issues:
   - Image not found on Docker Hub
   - KUBECONFIG secret incorrect
   - Timeout waiting for pods

### Pod Not Starting

```bash
# Check pod status
kubectl describe pod <pod-name> -n saferoute

# Check logs
kubectl logs <pod-name> -n saferoute

# Check events
kubectl get events -n saferoute --sort-by='.lastTimestamp'
```

### Image Pull Errors

```bash
# Verify image exists
docker manifest inspect saferoute/user-management:v1.0.0

# Check deployment image
kubectl get deployment user-management -n saferoute -o yaml | grep image:
```

### Database Connection Issues

```bash
# Check database pods
kubectl get pods -n data

# Check PostgreSQL logs
kubectl logs postgresql-0 -n data

# Test connection from pod
kubectl exec -it <pod-name> -n saferoute -- \
  nc -zv postgresql.data.svc.cluster.local 5432
```

## CI/CD Integration

### Workflow in Service Repositories

Add to your service CI workflow:

```yaml
- name: Trigger deployment
  run: |
    curl -X POST \
      -H "Accept: application/vnd.github.v3+json" \
      -H "Authorization: token ${{ secrets.MANIFEST_REPO_TOKEN }}" \
      https://api.github.com/repos/YOUR_ORG/saferoute-manifest/dispatches \
      -d '{
        "event_type": "deploy-service",
        "client_payload": {
          "service": "user-management",
          "image_tag": "${{ github.sha }}",
          "environment": "staging"
        }
      }'
```

See `.github/workflow-examples/service-ci-example.yml` for complete example.

## GitHub Secrets Required

Configure in repository settings:

- `KUBECONFIG`: Base64-encoded kubeconfig file
  ```bash
  cat ~/.kube/config | base64
  ```

## Best Practices

1. **Use specific image tags** in production (avoid `latest`)
2. **Test in staging first** before deploying to production
3. **Monitor deployments** through GitHub Actions
4. **Keep secrets secure** and rotate regularly
5. **Review resource limits** and adjust based on usage
6. **Enable HPA** for services with variable load
7. **Backup databases** regularly

## Monitoring

### Prometheus

```bash
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
# Open: http://localhost:9090
```

### Grafana

```bash
kubectl port-forward svc/grafana 3000:3000 -n monitoring
# Open: http://localhost:3000
```

## Support

- Check logs: `kubectl logs -f deployment/<service> -n saferoute`
- Review events: `kubectl get events -n saferoute`
- GitHub Actions logs: Actions tab
- Contact: DevOps team
