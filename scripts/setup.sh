#!/bin/bash
# =============================================================================
# setup.sh  —  Full one-shot setup for the K8s Cost Optimization Demo
# =============================================================================
# Resource note:
#   Baseline workloads request 3500m CPU + 3.5Gi RAM.
#   Monitoring stack (Prometheus, Grafana, kube-state-metrics, node-exporter,
#   OpenCost) needs another ~2 CPU and ~2 Gi RAM.
#   Therefore Minikube is started with 6 CPUs and 8 Gi RAM.
#   If your machine has less than 10 Gi free RAM, reduce --memory to 6144
#   and increase --cpus only if you have the cores.
#
# Run this script from WSL2 after installing Docker Desktop + Minikube + Helm.
# It walks through every phase and pauses at key points to let you verify.
#
# Usage: bash setup.sh [--skip-monitoring] [--skip-opencost]
# =============================================================================
set -euo pipefail

SKIP_MONITORING=false
SKIP_OPENCOST=false
for arg in "$@"; do
  [[ "$arg" == "--skip-monitoring" ]] && SKIP_MONITORING=true
  [[ "$arg" == "--skip-opencost"  ]] && SKIP_OPENCOST=true
done

info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[ OK ]\033[0m  $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
pause() { echo ""; read -rp "  ↵  Press ENTER to continue …" _; echo ""; }

# ── PHASE 1: Pre-flight ───────────────────────────────────────────────────────
info "PHASE 1 — Pre-flight checks"

for cmd in minikube kubectl helm docker; do
  if command -v "$cmd" &>/dev/null; then
    ok "$cmd found: $(command -v "$cmd")"
  else
    echo -e "\033[1;31m[FAIL]\033[0m  $cmd not found. Install it before running this script."
    exit 1
  fi
done

# ── PHASE 2: Start Minikube ───────────────────────────────────────────────────
info "PHASE 2 — Starting Minikube (6 CPUs, 8Gi RAM)"

# Pre-flight RAM check (Linux/WSL2 only)
if command -v free &>/dev/null; then
  FREE_MB=$(free -m | awk '/^Mem:/{print $7}')
  if [ "$FREE_MB" -lt 8192 ]; then
    warn "Only ${FREE_MB} MB RAM free. Recommended: ≥10 GB."
    warn "If pods go Pending, reduce baseline workload requests or lower"
    warn "Minikube --memory to match available RAM."
    warn "Continuing in 5 s — Ctrl+C to abort."
    sleep 5
  fi
fi

minikube start --cpus=6 --memory=8192 --driver=docker || {
  warn "Minikube already running. Continuing …"
}
ok "Minikube started."
minikube status

# ── PHASE 3: Enable addons ────────────────────────────────────────────────────
info "PHASE 3 — Enabling Minikube addons"
minikube addons enable metrics-server
minikube addons enable ingress 2>/dev/null || true
ok "Addons enabled."

# ── PHASE 4: Deploy workloads ─────────────────────────────────────────────────
info "PHASE 4 — Deploying BASELINE workloads to namespace: cost-demo"
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/api-deployment.yaml
kubectl apply -f k8s/worker-deployment.yaml
kubectl apply -f k8s/report-deployment.yaml
kubectl apply -f k8s/services.yaml

info "Waiting for pods to become Ready …"
kubectl rollout status deployment/api-service        -n cost-demo --timeout=120s
kubectl rollout status deployment/background-worker  -n cost-demo --timeout=120s
kubectl rollout status deployment/report-service     -n cost-demo --timeout=120s

ok "Baseline workloads deployed."
kubectl get pods -n cost-demo

# Resource pressure check — warn if any pod is Pending
PENDING=$(kubectl get pods -n cost-demo --no-headers | grep -c 'Pending' || true)
if [ "$PENDING" -gt 0 ]; then
  warn "$PENDING pod(s) are still Pending. This usually means Minikube has"
  warn "insufficient CPU or memory. Run: kubectl describe pod -n cost-demo"
  warn "to see the exact reason. You may need to:"
  warn "  1. Stop Minikube: minikube stop"
  warn "  2. Increase resources: minikube start --cpus=6 --memory=10240"
  warn "  3. Or reduce baseline workload requests in k8s/*.yaml"
fi
pause

# ── PHASE 5: Install Prometheus + Grafana ─────────────────────────────────────
if [ "$SKIP_MONITORING" = false ]; then
  info "PHASE 5 — Installing Prometheus + Grafana (kube-prometheus-stack)"
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo update

  kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

  helm upgrade --install kube-prom-stack prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --values monitoring/prometheus/values.yaml \
    --wait --timeout 10m

  ok "Prometheus + Grafana installed."
  kubectl get pods -n monitoring
  pause
else
  warn "Skipping Prometheus/Grafana installation (--skip-monitoring)."
fi

# ── PHASE 6: Install OpenCost ─────────────────────────────────────────────────
if [ "$SKIP_OPENCOST" = false ]; then
  info "PHASE 6 — Installing OpenCost"
  helm repo add opencost https://opencost.github.io/opencost-helm-chart
  helm repo update

  helm upgrade --install opencost opencost/opencost \
    --namespace opencost \
    --create-namespace \
    --values opencost/values.yaml \
    --wait --timeout 5m

  ok "OpenCost installed."
  kubectl get pods -n opencost
  pause
else
  warn "Skipping OpenCost installation (--skip-opencost)."
fi

# ── PHASE 7: Load Grafana dashboard ──────────────────────────────────────────
if [ "$SKIP_MONITORING" = false ]; then
  info "PHASE 7 — Importing Grafana dashboard"
  kubectl create configmap grafana-dashboards \
    --from-file=k8s-cost-optimization.json=monitoring/grafana/dashboard.json \
    -n monitoring \
    --dry-run=client -o yaml | kubectl apply -f -
  ok "Dashboard ConfigMap created."
fi

# ── PHASE 8: Print access URLs ────────────────────────────────────────────────
MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "127.0.0.1")

echo ""
echo "============================================================"
echo "  Setup complete!  Access points:"
echo ""
echo "  Grafana    → http://$MINIKUBE_IP:32000"
echo "              (user: admin  pass: devops-demo-2024)"
echo ""
echo "  OpenCost   → http://$MINIKUBE_IP:32090"
echo ""
echo "  Or use port-forward for NodePort alternatives:"
echo "    kubectl port-forward svc/kube-prom-stack-grafana 3000:80 -n monitoring"
echo "    kubectl port-forward svc/opencost -n opencost 9090:9090"
echo ""
echo "  Next steps:"
echo "    1. Run load test  : bash load-testing/load-test.sh medium"
echo "    2. Wait 2 min     : kubectl top pods -n cost-demo"
echo "    3. Collect baseline: bash scripts/collect-baseline.sh"
echo "    4. Apply optimised : kubectl apply -f k8s/optimized-deployments.yaml"
echo "    5. Collect after   : bash scripts/collect-after.sh"
echo "============================================================"
