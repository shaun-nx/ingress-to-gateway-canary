# Makefile for ingress-to-gateway-canary
# Convenience targets to deploy, verify, test, and undeploy the example.

NAMESPACE ?= ingress-to-gateway-canary
MANIFEST  ?= examples/ingress-to-gateway-canary/manifest.yaml
HOST      ?= canary.127.0.0.1.nip.io

.PHONY: help deploy verify test test-once undeploy

help:
	@echo "Available targets:"
	@echo "  make deploy      - Apply the manifests"
	@echo "  make verify      - List key resources in the example namespace"
	@echo "  make test-once   - Issue a single request to the host"
	@echo "  make test        - Issue 30 requests and tally Gateway vs Ingress hits"
	@echo "  make undeploy    - Delete the manifests"
	@echo "  make install-ingress-controller   - Install NGINX Ingress Controller (OSS) via Helm"
	@echo "  make install-gateway-controller   - Install NGINX Gateway Fabric (OSS) via Helm"
	@echo "  make deploy-virtualserver         - Apply NIC VirtualServer split (optional)"
	@echo "  make kind-create                  - Create a kind cluster"
	@echo "  make kind-delete                  - Delete the kind cluster"
	@echo "  make minikube-start               - Start a Minikube cluster"
	@echo "  make minikube-stop                - Stop the Minikube cluster"
	@echo "  make minikube-delete              - Delete the Minikube cluster"

deploy:
	kubectl apply -f $(MANIFEST)

verify:
	kubectl get ns $(NAMESPACE)
	kubectl get deploy,svc,ingress -n $(NAMESPACE)
	kubectl get gateways,httproutes -n $(NAMESPACE)

test-once:
	curl -sS http://$(HOST)/ | head -n 20

# Prints 'gateway' when X-From-Gateway header is present in the echoed response,
# otherwise 'ingress'. Tallies the Gateway hits out of 30 total requests.
test:
	@count=0; total=30; \
	for i in `seq 1 $$total`; do \
	  if curl -sS http://$(HOST)/ | grep -qi "X-From-Gateway"; then \
	    echo "gateway"; count=$$((count+1)); \
	  else \
	    echo "ingress"; \
	  fi; \
	done; \
	echo "Gateway hits: $$count / $$total"

undeploy:
	kubectl delete -f $(MANIFEST)

# ------------------------------------------------------------------------------
# Controller installation via Helm (Open Source NGINX)
# ------------------------------------------------------------------------------
HELM_REPO ?= nginx-stable
HELM_REPO_URL ?= https://helm.nginx.com/stable

.PHONY: helm-repo install-ingress-controller uninstall-ingress-controller print-ingress \
        install-gateway-controller uninstall-gateway-controller print-gateway

# Add and update the NGINX Helm repo
helm-repo:
	helm repo add $(HELM_REPO) $(HELM_REPO_URL) || true
	helm repo update

# Install NGINX Ingress Controller (OSS)
# Notes:
#  - Uses nginx/kubernetes-ingress Helm chart (nginx-stable/nginx-ingress)
#  - Explicitly sets controller.nginxplus=false to ensure OSS NGINX
#  - Exposes a LoadBalancer Service (adjust for your environment)
install-ingress-controller: helm-repo
	helm upgrade --install nginx-ingress $(HELM_REPO)/nginx-ingress \
	  --namespace nginx-ingress --create-namespace \
	  --set controller.nginxplus=false \
	  --set controller.enableCustomResources=true \
	  --set controller.service.type=LoadBalancer

uninstall-ingress-controller:
	-helm uninstall nginx-ingress -n nginx-ingress || true
	-kubectl delete ns nginx-ingress --wait=false || true

print-ingress:
	kubectl get pods,svc -n nginx-ingress
	kubectl get ingressclasses
	kubectl get ingress -A

# Install NGINX Gateway Fabric (OSS)
# Notes:
#  - Uses nginx/nginx-gateway-fabric Helm chart (nginx-stable/nginx-gateway-fabric)
#  - Defaults to OSS unless NGINX Plus flags are set; we do not set any Plus flags here.
install-gateway-controller: helm-repo
	helm upgrade --install nginx-gateway $(HELM_REPO)/nginx-gateway-fabric \
	  --namespace nginx-gateway --create-namespace

uninstall-gateway-controller:
	-helm uninstall nginx-gateway -n nginx-gateway || true
	-kubectl delete ns nginx-gateway --wait=false || true

print-gateway:
	kubectl get pods,svc -n nginx-gateway
	kubectl get gatewayclasses
	kubectl get gateways,httproutes -A

.PHONY: deploy-virtualserver switch-to-nic
# Apply NIC VirtualServer-based 80/20 split (hello-v1 : gateway-bridge)
deploy-virtualserver:
	kubectl apply -f examples/ingress-to-gateway-canary/virtualserver.yaml

# If you used the Ingress canary example first, switch to NIC VirtualServer:
# - delete the Ingress resources and apply the VirtualServer
switch-to-nic:
	-kubectl delete ingress hello-primary hello-canary -n $(NAMESPACE) || true
	kubectl apply -f examples/ingress-to-gateway-canary/virtualserver.yaml

# ------------------------------------------------------------------------------
# Local cluster helpers
# ------------------------------------------------------------------------------
KIND_CLUSTER ?= itg-canary
MINIKUBE_PROFILE ?= itg-canary
MINIKUBE_DRIVER ?= docker

.PHONY: kind-create kind-delete minikube-start minikube-stop minikube-delete

# Create a kind cluster (default name: itg-canary)
kind-create:
	kind create cluster --name $(KIND_CLUSTER)

# Delete the kind cluster
kind-delete:
	-kind delete cluster --name $(KIND_CLUSTER) || true

# Start a Minikube cluster (default profile: itg-canary, driver: docker)
minikube-start:
	minikube start -p $(MINIKUBE_PROFILE) --driver=$(MINIKUBE_DRIVER)

# Stop the Minikube cluster
minikube-stop:
	-minikube stop -p $(MINIKUBE_PROFILE) || true

# Delete the Minikube cluster
minikube-delete:
	-minikube delete -p $(MINIKUBE_PROFILE) || true
