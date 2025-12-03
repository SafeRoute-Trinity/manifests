# HTTPS/TLS Configuration with cert-manager

This directory contains the configuration for enabling HTTPS on all ingress resources using cert-manager and Let's Encrypt.

## Prerequisites

1. **cert-manager installed** in your Kubernetes cluster
2. **nginx ingress controller** installed and configured
3. **DuckDNS domains** properly configured and pointing to your cluster's ingress IP

## Installation Steps

### 1. Install cert-manager

If cert-manager is not already installed, install it:

```bash
# Install cert-manager CRDs
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
```

### 2. Configure ClusterIssuer

**IMPORTANT**: Before applying, update the email address in `cluster-issuer.yml`:

```bash
# Edit the file and replace your-email@example.com with your actual email
# This email is used for Let's Encrypt registration and expiration notices
```

Then apply the ClusterIssuer:

```bash
kubectl apply -f k8s/cert-manager/cluster-issuer.yml
```

### 3. Verify ClusterIssuer

```bash
kubectl get clusterissuer
```

You should see both `letsencrypt-prod` and `letsencrypt-staging` issuers.

### 4. Apply Updated Ingress Resources

All ingress resources have been updated with TLS configuration. Apply them:

```bash
# Apply all ingress resources
kubectl apply -f k8s/saferoute/ingress.yml
kubectl apply -f k8s/saferoute/api-ingress.yml
kubectl apply -f k8s/monitoring/grafana-ingress.yml
kubectl apply -f k8s/saferoute/rabbitmq-ingress.yml
```

### 5. Monitor Certificate Provisioning

cert-manager will automatically create Certificate resources and request certificates from Let's Encrypt:

```bash
# Check certificate status
kubectl get certificates -A

# Check certificate requests
kubectl get certificaterequests -A

# Check cert-manager logs if there are issues
kubectl logs -n cert-manager -l app.kubernetes.io/instance=cert-manager
```

### 6. Verify HTTPS

Once certificates are issued (usually takes 1-2 minutes), verify HTTPS is working:

```bash
# Test HTTPS endpoint
curl -I https://saferoutemap.duckdns.org/health/user-management

# Check certificate details
openssl s_client -connect saferoutemap.duckdns.org:443 -servername saferoutemap.duckdns.org
```

## How It Works

1. **ClusterIssuer**: Defines Let's Encrypt as the certificate authority
2. **Ingress TLS**: Each ingress specifies TLS hosts and a secret name for the certificate
3. **cert-manager**: Automatically creates Certificate resources and requests certificates
4. **HTTP-01 Challenge**: Let's Encrypt validates domain ownership via HTTP challenge
5. **Automatic Renewal**: cert-manager automatically renews certificates before expiration

## Certificate Secrets

cert-manager creates TLS secrets automatically:
- `saferoutemap-duckdns-tls` (for saferoutemap.duckdns.org)
- `saferouterabbitmq-duckdns-tls` (for saferouterabbitmq.duckdns.org)

These secrets are created in the same namespace as the ingress resource.

## Testing with Staging

Before using production Let's Encrypt (which has rate limits), you can test with staging:

1. Update ingress annotations to use `letsencrypt-staging`:
   ```yaml
   cert-manager.io/cluster-issuer: "letsencrypt-staging"
   ```

2. Apply and test

3. Once verified, switch back to `letsencrypt-prod`

## Troubleshooting

### Certificate Not Issued

```bash
# Check certificate status
kubectl describe certificate saferoutemap-duckdns-tls -n saferoute

# Check certificate request
kubectl describe certificaterequest -n saferoute

# Check cert-manager logs
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager
```

### Common Issues

1. **DNS not resolving**: Ensure DuckDNS domains point to your ingress IP
2. **HTTP-01 challenge failing**: Ensure ingress controller is accessible on port 80
3. **Rate limiting**: Use staging issuer for testing
4. **Wrong email**: Update email in ClusterIssuer configuration

### Force Certificate Renewal

```bash
# Delete the certificate secret to force renewal
kubectl delete secret saferoutemap-duckdns-tls -n saferoute

# cert-manager will automatically recreate it
```

## HTTP to HTTPS Redirect

All ingress resources are configured with:
- `nginx.ingress.kubernetes.io/ssl-redirect: "true"`
- `nginx.ingress.kubernetes.io/force-ssl-redirect: "true"`

This automatically redirects all HTTP traffic to HTTPS.

## References

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt](https://letsencrypt.org/)
- [nginx Ingress Controller](https://kubernetes.github.io/ingress-nginx/)

