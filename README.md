# Ingress to Gateway canary

## Overview

This repo provides a minimal  example for the following scenario:
- You currently have an Ingress Controller and an Ingress resource routing to your app (v1).
- You want to canary a small percentage of traffic to a new Gateway API deployment (v2) managed by a Gateway controller.
- The example keeps configuration minimal and avoids external 3rd party tools. It uses a tiny in-cluster nginx reverse-proxy “bridge” as Ingress backends must be Services and cannot directly reference a Gateway listener.

## Approach
- Primary Ingress sends traffic to hello-v1 (80%).
- A Canary Ingress (NGINX Ingress Controller canary feature) sends 20% to a “gateway-bridge” Service.
- The “gateway-bridge” is a small nginx:alpine reverse-proxy that forwards requests to the Gateway controller’s data plane Service while preserving the Host header.
- A Gateway and HTTPRoute process the canaried traffic and route it to hello-v2.
- The HTTPRoute injects a header X-From-Gateway: true so you can easily observe which responses were served via the Gateway path.

## Manifests

- Single manifest (namespace-scoped) with all necessary resources:
  - Namespace: `ingress-to-gateway-canary`
  - hello-v1 Deployment/Service (Ingress primary, ~80%)
  - hello-v2 Deployment/Service (Gateway backend)
  - Gateway + HTTPRoute for host `canary.127.0.0.1.nip.io`
  - gateway-bridge ConfigMap/Deployment/Service (nginx reverse-proxy to Gateway)
  - Primary Ingress (hello-v1)
  - Canary Ingress (20% to gateway-bridge)

Location: `examples/ingress-to-gateway-canary/manifest.yaml`

## Prerequisites

- Kubernetes cluster (kind, k3d, minikube, GKE, EKS, AKS, etc.). If you don't already have a cluster, you can create one locally:
  - kind: make kind-create (delete with make kind-delete)
  - Minikube: make minikube-start (stop with make minikube-stop, delete with make minikube-delete)
- kubectl configured for your cluster
- An Ingress Controller (example uses ingressClassName: nginx)
  - If using a different Ingress controller, adjust spec.ingressClassName and, if needed, canary configuration (the percentage-based canary in this example uses NGINX-specific annotations).
- Gateway API CRDs and a Gateway Controller installed
  - This example assumes a GatewayClass named nginx and that the controller’s data plane Service is reachable inside the cluster.
  - The included bridge defaults to upstream host: nginx-gateway.nginx-gateway.svc.cluster.local:80 (NGINX Gateway Fabric). If your controller uses a different Service name/namespace/port, update the ConfigMap in the manifest accordingly.
- curl for testing
- Hostname resolution to your data plane endpoints
  - The manifests use canary.127.0.0.1.nip.io (nip.io resolves to 127.0.0.1). Ensure your Ingress and Gateway data planes are reachable from your host at ports 80/443 as appropriate for your environment, or change the hostnames to match your setup.

## Controller Installation (Helm, OSS NGINX)

- Install NGINX Ingress Controller (OSS) via Helm:
  make install-ingress-controller
  make print-ingress
- Install NGINX Gateway Fabric (OSS) via Helm:
  make install-gateway-controller
  make print-gateway
- Confirm:
  - IngressClass named "nginx" exists: kubectl get ingressclasses
  - GatewayClass named "nginx" exists: kubectl get gatewayclasses
  - Data planes are reachable at your chosen endpoints (nip.io hostnames assume 127.0.0.1 reachable on ports 80/443)

## Quickstart

0) Create a local cluster (if needed):
   - kind: make kind-create
   - Minikube: make minikube-start
   Ensure your kubectl context points to the new cluster.

1) Apply the example:
   kubectl apply -f examples/ingress-to-gateway-canary/manifest.yaml

2) Verify resources:
   kubectl get ns ingress-to-gateway-canary
   kubectl get deploy,svc,ingress -n ingress-to-gateway-canary
   kubectl get gateways,httproutes -n ingress-to-gateway-canary

3) Test traffic distribution:
   - Single request (likely v1 path via Ingress):
     curl -sS http://canary.127.0.0.1.nip.io/ | head -n 20

   - Sample multiple requests and observe canary via Gateway (~20% should include X-From-Gateway: true in the HTML echoed headers):
     for i in {1..30}; do
       curl -sS http://canary.127.0.0.1.nip.io/ | grep -i "X-From-Gateway" || echo "no-gateway-header"
     done

   You should see roughly 20% of lines containing X-From-Gateway: true. The exact ratio will vary with small sample sizes.

4) Adjust the canary percentage:
   - Edit the annotation nginx.ingress.kubernetes.io/canary-weight in the canary Ingress (hello-canary) to your desired integer percentage (0–100), e.g. "5", "20", "50", etc., then re-apply the manifest or use kubectl patch.

## Cleanup

kubectl delete -f examples/ingress-to-gateway-canary/manifest.yaml

## Customization

- Ingress class:
  - Change spec.ingressClassName in both Ingress resources if your controller is not nginx.
- Canary percentage:
  - Update metadata.annotations["nginx.ingress.kubernetes.io/canary-weight"] in the hello-canary Ingress.
- Hostnames:
  - Update canary.127.0.0.1.nip.io in the Ingress and HTTPRoute to match your environment (e.g., canary.<your-ip>.nip.io or a DNS name you control).
- Gateway controller:
  - If you are not using NGINX Gateway Fabric, change the bridge’s upstream in:
    examples/ingress-to-gateway-canary/manifest.yaml
    - ConfigMap gateway-bridge-nginx-conf, key nginx.conf:
      upstream gateway_dp {
        server <your-gateway-dataplane-service>.<ns>.svc.cluster.local:<port>;
      }
- Listener/TLS:
  - This example uses HTTP on port 80 for simplicity. To use HTTPS/TLS, configure a TLS-enabled Gateway listener and corresponding secrets per your controller’s documentation, and update the bridge upstream port if needed.

## Notes and Caveats

- Ingress percentage-based canary is controller-specific:
  - This example uses NGINX Ingress annotations:
    - nginx.ingress.kubernetes.io/canary: "true"
    - nginx.ingress.kubernetes.io/canary-weight: "20"
  - If you use a different Ingress controller, adapt to its canary mechanism (if supported).
- The “bridge” reverse-proxy exists because Ingress backends must be Services, while a Gateway listener is not a Service. This bridge is a minimal nginx:alpine Deployment and ConfigMap, not an external 3rd party tool.
- The bridge preserves the Host header so that the Gateway’s HTTPRoute can match the same host (canary.127.0.0.1.nip.io).
- Both hello-v1 and hello-v2 use the same nginxdemos/hello image for simplicity. The HTTPRoute injects X-From-Gateway: true so you can distinguish Gateway-served responses in the echoed headers.
