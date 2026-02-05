# Service Health Monitoring Setup

This directory contains the configuration for monitoring SafeRoute service health checks using Prometheus Blackbox Exporter and Grafana.

## Components

- **Blackbox Exporter**: Probes HTTP endpoints to check service health
- **Prometheus**: Scrapes health check metrics from Blackbox Exporter
- **Grafana Dashboard**: Visualizes service health status and metrics

## Deployment Steps

### 1. Deploy Blackbox Exporter

```bash
# Apply blackbox exporter configuration
kubectl apply -f k8s/monitoring/blackbox-exporter/configmap.yml
kubectl apply -f k8s/monitoring/blackbox-exporter/deployment.yml
kubectl apply -f k8s/monitoring/blackbox-exporter/service.yml

# Verify deployment
kubectl get pods -n monitoring -l app=blackbox-exporter
kubectl logs -n monitoring -l app=blackbox-exporter
```

### 2. Update Prometheus Configuration

The Prometheus configuration has been updated to include health check probing. Apply the updated config:

```bash
# Apply updated Prometheus configuration
kubectl apply -f k8s/monitoring/prometheus/configmap.yml

# Restart Prometheus to pick up new configuration
kubectl rollout restart deployment prometheus -n monitoring

# Verify Prometheus is scraping health checks
# Port-forward to Prometheus UI
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Then visit http://localhost:9090/targets and look for the "blackbox-healthchecks" job
```

### 3. Import Grafana Dashboard

There are two ways to import the dashboard:

#### Option A: Import via Grafana UI (Recommended)

1. Port-forward to Grafana:
   ```bash
   kubectl port-forward -n monitoring svc/grafana 3000:3000
   ```

2. Open Grafana at http://localhost:3000 (or your configured URL)
   - Default credentials: admin/admin

3. Import the dashboard:
   - Click "+" → "Import" in the left sidebar
   - Click "Upload JSON file"
   - Select `k8s/monitoring/grafana/dashboards/service-health-dashboard.json`
   - Select your Prometheus datasource
   - Click "Import"

#### Option B: Auto-provision the Dashboard

Create a ConfigMap and configure Grafana to auto-load dashboards:

```bash
# Create dashboard ConfigMap
kubectl create configmap grafana-dashboard-health \
  --from-file=service-health-dashboard.json=k8s/monitoring/grafana/dashboards/service-health-dashboard.json \
  -n monitoring

# Update Grafana deployment to mount dashboard (requires Helm or manual config)
```

## Dashboard Features

The **SafeRoute Services Health Dashboard** includes:

1. **Service Health Status Overview**: Visual status of all services (UP/DOWN)
2. **Health Check Success Rate**: Overall system health percentage
3. **Services Currently Down**: Count of unhealthy services
4. **Health Check Response Time**: Timeline of response times for each service
5. **Health Check History**: Historical up/down status
6. **HTTP Status Codes**: Current HTTP response codes from each service
7. **SSL Certificate Expiry**: Days until SSL certificates expire (if applicable)
8. **Individual Service Details**: Detailed table with all metrics per service

## Monitored Services

The following services are monitored:

- **user-management** (`http://user-management.saferoute.svc.cluster.local/health`)
- **routing-service** (`http://routing-service.saferoute.svc.cluster.local/health`)
- **safety-scoring** (`http://safety-scoring.saferoute.svc.cluster.local/health`)
- **feedback** (`http://feedback.saferoute.svc.cluster.local/health`)
- **notification-service** (`http://notification-service.saferoute.svc.cluster.local/health`)
- **sos** (`http://sos.saferoute.svc.cluster.local/health`)
- **rabbitmq** (`http://rabbitmq.data.svc.cluster.local:15672/api/health/checks/alarms`)
- **postgresql** (`http://postgresql.data.svc.cluster.local:5432`)

## Prometheus Queries Used

Key queries used in the dashboard:

- **Service Up/Down**: `probe_success{job="blackbox-healthchecks"}`
- **Response Time**: `probe_duration_seconds{job="blackbox-healthchecks"}`
- **HTTP Status**: `probe_http_status_code{job="blackbox-healthchecks"}`
- **Success Rate**: `avg(probe_success{job="blackbox-healthchecks"}) * 100`

## Alerting (Optional)

You can set up Prometheus alerts for health check failures. Add to your Prometheus configuration:

```yaml
groups:
- name: service_health
  interval: 30s
  rules:
  - alert: ServiceDown
    expr: probe_success{job="blackbox-healthchecks"} == 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Service {{ $labels.instance }} is down"
      description: "{{ $labels.instance }} has been down for more than 2 minutes"
  
  - alert: ServiceSlowResponse
    expr: probe_duration_seconds{job="blackbox-healthchecks"} > 1
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Service {{ $labels.instance }} is responding slowly"
      description: "{{ $labels.instance }} response time is {{ $value }}s"
```

## Troubleshooting

### Blackbox Exporter not probing

Check logs:
```bash
kubectl logs -n monitoring -l app=blackbox-exporter
```

### Prometheus not scraping

1. Check Prometheus targets: http://localhost:9090/targets
2. Look for the "blackbox-healthchecks" job
3. Check for errors in the status column

### Dashboard shows no data

1. Verify Prometheus datasource is configured in Grafana
2. Check that metrics are being collected: `probe_success{job="blackbox-healthchecks"}`
3. Verify time range in dashboard

### Add new service to monitoring

Edit `k8s/monitoring/prometheus/configmap.yml` and add the new service URL to the `blackbox-healthchecks` job targets:

```yaml
- targets:
  - http://new-service.saferoute.svc.cluster.local/health
```

Then restart Prometheus:
```bash
kubectl rollout restart deployment prometheus -n monitoring
```

## Customization

### Change probe interval

Edit the Prometheus ConfigMap and modify `scrape_interval` for the `blackbox-healthchecks` job.

### Add custom health check modules

Edit `k8s/monitoring/blackbox-exporter/configmap.yml` to add new probe modules (e.g., TCP, ICMP, DNS).

### Customize dashboard

1. Make changes in Grafana UI
2. Export the updated JSON
3. Save to `k8s/monitoring/grafana/dashboards/service-health-dashboard.json`
