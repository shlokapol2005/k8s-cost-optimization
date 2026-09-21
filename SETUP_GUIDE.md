# SETUP_GUIDE.md — Complete Step-by-Step Installation

> Follow every step in order. Each phase maps to the project phases described in the report.

---

## Prerequisites — Install These First (Windows)

Before opening WSL2 or a terminal, install the following on **Windows**:

| Software | Download Link | Notes |
|----------|--------------|-------|
| **Docker Desktop** | https://docs.docker.com/desktop/install/windows-install/ | Enable WSL2 integration |
| **WSL2 + Ubuntu** | Run `wsl --install` in PowerShell (Admin) | Ubuntu 22.04 recommended |
| **Minikube** | https://minikube.sigs.k8s.io/docs/start/ | Install inside WSL2 |
| **kubectl** | https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/ | Install inside WSL2 |
| **Helm** | https://helm.sh/docs/intro/install/ | Install inside WSL2 |
| **Git** | Pre-installed on Ubuntu | — |

---

## Phase 1 — Install Tools Inside WSL2

Open **WSL2 Ubuntu** terminal and run:

```bash
# ── kubectl ────────────────────────────────────────────────────────────────
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client

# ── Minikube ──────────────────────────────────────────────────────────────
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
minikube version

# ── Helm ──────────────────────────────────────────────────────────────────
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

**Verify Docker is accessible from WSL2:**
```bash
docker info | head -5
# Should show Docker server info — if error, open Docker Desktop → Settings → WSL Integration → enable Ubuntu
```

---

## Phase 2 — Start Minikube

```bash
# Start with enough resources for 3 workloads + monitoring stack
minikube start --cpus=6 --memory=8192 --driver=docker
minikube addons enable metrics-server
kubectl get nodes
```

> ⚠️ **RAM note:** The baseline workloads (3.5 CPU / 3.5 Gi) plus the monitoring stack (~2 CPU / 2 Gi) together need ~5.5 CPU and ~5.5 Gi. Use **at least 6 CPUs and 8 Gi** for Minikube. If your laptop has less than 10 Gi free RAM, reduce `--memory=6144` but expect pods to be tight.

Expected output:
```
NAME       STATUS   ROLES           AGE   VERSION
minikube   Ready    control-plane   30s   v1.28.x
```

---

## Phase 3 — Clone the Repository

```bash
git clone <your-github-repo-url>
cd devops-theoryIA      # or whatever the folder is named
```

---

## Phase 4 — Deploy Baseline Workloads

```bash
# Create the namespace
kubectl apply -f k8s/namespace.yaml

# Deploy all baseline workloads
kubectl apply -f k8s/api-deployment.yaml
kubectl apply -f k8s/worker-deployment.yaml
kubectl apply -f k8s/report-deployment.yaml
kubectl apply -f k8s/services.yaml

# Wait for them to be Running
kubectl rollout status deployment/api-service       -n cost-demo --timeout=120s
kubectl rollout status deployment/background-worker -n cost-demo --timeout=120s
kubectl rollout status deployment/report-service    -n cost-demo --timeout=120s

# Verify
kubectl get pods -n cost-demo
kubectl get deployments -n cost-demo
kubectl get services -n cost-demo
```

Expected output:
```
NAME                          READY   STATUS    RESTARTS
api-service-xxx               1/1     Running   0
background-worker-xxx         1/1     Running   0
report-service-xxx            1/1     Running   0
```

---

## Phase 5 — Install Prometheus + Grafana

```bash
# Add the Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create monitoring namespace
kubectl create namespace monitoring

# Install kube-prometheus-stack
helm upgrade --install kube-prom-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values monitoring/prometheus/values.yaml \
  --wait --timeout 10m

# Verify
kubectl get pods -n monitoring
```

Wait until all pods are `Running/Ready`. This can take 3–5 minutes.

### Access Grafana

```bash
# Option A — NodePort (if minikube tunnels work)
minikube service kube-prom-stack-grafana -n monitoring --url

# Option B — Port Forward (always works)
kubectl port-forward svc/kube-prom-stack-grafana 3000:80 -n monitoring &
# Open: http://localhost:3000
# Login: admin / devops-demo-2024
```

---

## Phase 6 — Install OpenCost

```bash
# Add OpenCost Helm repo
helm repo add opencost https://opencost.github.io/opencost-helm-chart
helm repo update

# Install OpenCost
helm upgrade --install opencost opencost/opencost \
  --namespace opencost \
  --create-namespace \
  --values opencost/values.yaml \
  --wait --timeout 5m

# Verify
kubectl get pods -n opencost
```

### Access OpenCost UI

```bash
# STEP A — find the actual Prometheus service name BEFORE installing OpenCost
kubectl get svc -n monitoring | grep -i prometheus
# Look for a service on port 9090 — copy its exact NAME
# Example names:
#   kube-prom-stack-kube-prome-prometheus
#   prometheus-operated

# STEP B — edit opencost/values.yaml and set:
#   opencost.prometheus.internal.serviceName: "<name you found above>"
# Then install:
helm upgrade --install opencost opencost/opencost \
  --namespace opencost --create-namespace \
  --values opencost/values.yaml \
  --wait --timeout 5m

kubectl get pods -n opencost
```

### Access OpenCost

```bash
# UI is on port 9090, API/server on port 9003
kubectl port-forward svc/opencost -n opencost 9090:9090 9003:9003
# Open browser:
#   UI  → http://localhost:9090
#   API → http://localhost:9003
```

---

## Phase 7 — Import the Grafana Dashboard

1. Open Grafana: `http://localhost:3000`
2. Login: `admin` / `devops-demo-2024`
3. Left sidebar → **Dashboards** → **Import**
4. Click **"Upload JSON file"**
5. Select `monitoring/grafana/dashboard.json`
6. Set the Prometheus datasource → click **Import**

You should now see the **K8s Cost & Resource Optimization** dashboard.

---

### STEP 8 — Measure Baseline, Then Determine Optimized Values

```bash
# 1. Wait 2 minutes for metrics-server to warm up
kubectl top pods -n cost-demo

# 2. Run load test (medium, 120 seconds)
bash load-testing/load-test.sh medium

# 3. While load is running, observe CPU/memory
watch -n 5 kubectl top pods -n cost-demo

# 4. Collect baseline data → results/baseline.csv
bash scripts/collect-baseline.sh
```

📸 **Take screenshots** of Grafana and OpenCost now — these are your BEFORE screenshots.

> 🔑 **Key question to answer in your report:**
> "Why did you choose those optimized values?"
> **Answer:** Set `request = peak_observed_usage × 1.3`. For example, if `kubectl top` shows
> `report-service` using `85m CPU` at peak, a defensible optimized request is `~110m`.

### STEP 9 — Fill In Optimized Values and Apply

```bash
# Open the optimized manifest and replace REPLACE_AFTER_MEASUREMENT
# with your calculated values (peak_usage * 1.3 for requests, * 2 for limits)
nano k8s/optimized-deployments.yaml   # or use any editor

# Then apply:
kubectl apply -f k8s/optimized-deployments.yaml
kubectl rollout status deployment -n cost-demo --timeout=120s

# Verify new (lower) resource requests
kubectl get deployments -n cost-demo \
  -o custom-columns="NAME:.metadata.name,CPU:.spec.template.spec.containers[0].resources.requests.cpu,MEM:.spec.template.spec.containers[0].resources.requests.memory"
```

---

## Phase 11 — Run Load Test Again & Collect After Data

```bash
# Run same load level as before
bash load-testing/load-test.sh medium

# Collect optimized metrics
bash scripts/collect-after.sh
```

Check: `results/optimized.csv` and `results/comparison.txt`

---

## Phase 12 — Compare Results

```bash
cat results/comparison.txt
```

Also compare in Grafana:
- Switch the time range to show **before** period vs **after** period
- Screenshot both states for the report

---

## Demo Sequence (for Presentation)

Run these commands in order during your demo:

```bash
# 1. Show cluster is healthy
minikube status
kubectl get nodes

# 2. Show workloads
kubectl get pods -n cost-demo
kubectl get deployments -n cost-demo

# 3. Show resource requests (baseline)
kubectl get deployments -n cost-demo -o custom-columns="NAME:.metadata.name,CPU:.spec.template.spec.containers[0].resources.requests.cpu,MEM:.spec.template.spec.containers[0].resources.requests.memory"

# 4. Show live usage
kubectl top pods -n cost-demo

# 5. Open Grafana (http://localhost:3000) — show panels live

# 6. Open OpenCost (http://localhost:9003) — show allocation + cost

# 7. Point out the inefficiency:
#    "report-service requests 2000m CPU but uses only ~70m"

# 8. Apply optimization
kubectl apply -f k8s/optimized-deployments.yaml
kubectl rollout status deployment -n cost-demo

# 9. Show new resource requests
kubectl get deployments -n cost-demo -o custom-columns="NAME:.metadata.name,CPU:.spec.template.spec.containers[0].resources.requests.cpu,MEM:.spec.template.spec.containers[0].resources.requests.memory"

# 10. Show before/after in Grafana + OpenCost

# 11. Print comparison summary
cat results/comparison.txt
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `minikube start` fails | Ensure Docker Desktop is running and WSL2 integration is on |
| `kubectl top` shows no metrics | Run `minikube addons enable metrics-server` and wait 2 min |
| Grafana unreachable | Use port-forward: `kubectl port-forward svc/kube-prom-stack-grafana 3000:80 -n monitoring` |
| OpenCost shows $0 cost | Wait 5–10 min for OpenCost to scrape Prometheus data |
| Pods stuck `Pending` | Check node resources: `kubectl describe node minikube` |
| Helm install timeout | Increase timeout: `--timeout 15m` or check pod logs |

---

## GitHub Setup

```bash
# Initialize git and push
git init
git add .
git commit -m "feat: initial project setup – baseline workloads + monitoring"
git remote add origin <your-github-repo-url>
git push -u origin main
```

The GitHub Actions CI pipeline will automatically run on every push and validate your YAML/scripts.
