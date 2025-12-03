# RabbitMQ Deployment

RabbitMQ is deployed as a StatefulSet in the `data` namespace for internal cluster communication.

## Connection Details

### For Services Inside Kubernetes

Services should connect directly to RabbitMQ using the internal service DNS:

- **AMQP Connection**: `rabbitmq.data.svc.cluster.local:5672`
- **Management UI** (internal): `rabbitmq.data.svc.cluster.local:15672`
- **Metrics** (Prometheus): `rabbitmq.data.svc.cluster.local:15692`

### Connection String Format

```
amqp://<username>:<password>@rabbitmq.data.svc.cluster.local:5672/<vhost>
```

Example (using default vhost `/`):
```
amqp://admin:YOUR_PASSWORD@rabbitmq.data.svc.cluster.local:5672/
```

## Environment Variables for Services

Add these to your service's ConfigMap or Deployment:

```yaml
env:
- name: RABBITMQ_HOST
  value: "rabbitmq.data.svc.cluster.local"
- name: RABBITMQ_PORT
  value: "5672"
- name: RABBITMQ_USER
  valueFrom:
    secretKeyRef:
      name: rabbitmq-secret
      namespace: data
      key: username
- name: RABBITMQ_PASSWORD
  valueFrom:
    secretKeyRef:
      name: rabbitmq-secret
      namespace: data
      key: password
```

## Management UI Access

### Via Ingress (Configured)

The RabbitMQ Management UI is exposed via ingress at:
- **URL**: `http://saferoutemap.duckdns.org/rabbitmq`
- **Direct access**: `http://saferoutemap.duckdns.org/rabbitmq/`

**⚠️ Security Note**: The management UI is now publicly accessible. Ensure you:
- Use strong RabbitMQ credentials (set in the secret)
- Consider adding basic auth annotations to the ingress
- Enable TLS/HTTPS for production
- Restrict access via network policies if needed
- Monitor access logs

### Adding Basic Auth (Recommended)

To add basic authentication to the RabbitMQ management UI ingress route, you can add annotations:

```yaml
nginx.ingress.kubernetes.io/auth-type: basic
nginx.ingress.kubernetes.io/auth-secret: rabbitmq-auth
nginx.ingress.kubernetes.io/auth-realm: 'RabbitMQ Management - Authentication Required'
```

Then create the auth secret:
```bash
htpasswd -c auth rabbitmq-admin
kubectl create secret generic rabbitmq-auth --from-file=auth -n saferoute
```

## Why Not Expose AMQP via Ingress?

1. **Protocol Mismatch**: AMQP is not HTTP-based, so standard HTTP ingress won't work
2. **Performance**: Direct AMQP connections are more efficient
3. **Security**: Message queues should be internal to the cluster
4. **Best Practice**: Services should communicate via internal service mesh

## Troubleshooting

### Check RabbitMQ Status

```bash
kubectl get pods -n data -l app=rabbitmq
kubectl logs rabbitmq-0 -n data
```

### Test Connection from a Pod

```bash
# From any pod in the cluster
kubectl exec -it <pod-name> -n saferoute -- \
  nc -zv rabbitmq.data.svc.cluster.local 5672
```

### View RabbitMQ Logs

```bash
kubectl logs -f rabbitmq-0 -n data
```

### Access Management UI

```bash
kubectl port-forward svc/rabbitmq 15672:15672 -n data
# Then open http://localhost:15672 in your browser
```

