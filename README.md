# Kubernetes Cost Monitoring & Resource Optimization

> **Research Question:** How can Kubernetes resource requests and limits be optimized to reduce estimated infrastructure cost while maintaining application performance?

[![CI](https://github.com/shlokapol2005/k8s-cost-optimization/actions/workflows/ci.yaml/badge.svg)](https://github.com/shlokapol2005/k8s-cost-optimization/actions/workflows/ci.yaml)

---

## 🏆 Experiment Results (Real Data)

> All numbers below are **measured live** from the cluster — not estimated beforehand.

### Resource Optimization

| Workload | CPU Before | CPU After | Memory Before | Memory After |
|----------|-----------|-----------|---------------|--------------|
| `api-service` (×2) | 500m | **5m** | 512Mi | **20Mi** |
| `background-worker` | 1000m | **110m** | 1Gi | **32Mi** |
| `report-service` ⭐ | **2000m** | **5m** | **2Gi** | **20Mi** |
| **TOTAL** | **3500m** | **120m** | **~3.5Gi** | **~72Mi** |
| **Reduction** | — | **↓ 96.6%** | — | **↓ 98%** |

### OpenCost Estimated Cost (`cost-demo` namespace)

| Metric | BEFORE | AFTER | Reduction |
|--------|--------|-------|-----------|
| CPU Cost | $0.105370/hr | $0.000530/hr | **↓ 99.5%** |
| Memory Cost | $0.014120/hr | $0.000050/hr | **↓ 99.6%** |
| **Total Cost** | **$0.119490/hr** | **$0.000580/hr** | **↓ 99.5%** |
| Cluster Efficiency | 3.5% | 8.7% | ↑ 5.2pp |

> **Cost Disclaimer:** Values above are *estimated* resource allocation costs based on a custom pricing model (≈ AWS us-east-1 t3.medium rates: $0.031611/CPU-hr, $0.004237/GiB-hr) applied to local Minikube usage. They do not represent an actual cloud billing amount.

---

## Architecture

```
                         GitHub
                           │
                           ▼
                    GitHub Actions
                  YAML + Shell Validation
                           │
                           ▼
                     ┌───────────┐
                     │ Minikube  │
                     │ Kubernetes│
                     └─────┬─────┘
                           │
             ┌─────────────┼──────────────┐
             ▼             ▼              ▼
           API           Worker         Report
           Pod             Pod            Pod
             │       polls ↑              │
             └───────────┘               │
             ↑                            │
       Load Generator                     │
             │ HTTP traffic               │
             └────────────────────────────┘
                           │
                  ┌────────┴────────┐
                  ▼                 ▼
             Prometheus          OpenCost
                  │                 │
                  └────────┬────────┘
                           ▼
                        Grafana
                           │
             ┌─────────────┼─────────────┐
             ▼             ▼             ▼
          CPU/Memory     Allocation     Cost
          Dashboard      Dashboard     Dashboard
                           │
                           ▼
                  Optimization Analysis
                           │
                     ┌─────┴─────┐
                     ▼           ▼
                  BEFORE       AFTER
                  Metrics      Metrics
                     └─────┬─────┘
                           ▼
                    Cost Reduction /
                 Resource Optimization
```

> **Load chain:** Load Generator → `api-service` (HTTP) → `background-worker` polls `/work` endpoint → does CPU arithmetic. This means the worker's measured utilization is driven by real traffic, not an idle loop.

---

## Tools & Technologies

| Tool | Purpose |
|------|---------|
| **Kubernetes / Minikube** | Local container orchestration |
| **OpenCost** | Cost allocation & monitoring |
| **Prometheus** | Metrics collection |
| **Grafana** | Visualization & dashboards |
| **Helm** | Package management |
| **Docker Desktop** | Container runtime |
| **GitHub Actions** | CI – YAML/script validation |
| **WSL2** | Linux environment on Windows |

---

## Repository Structure

```
k8s-cost-optimization/
│
├── .github/
│   └── workflows/
│       └── ci.yaml                   ← GitHub Actions CI pipeline
│
├── k8s/
│   ├── namespace.yaml                ← cost-demo namespace
│   ├── api-deployment.yaml           ← Workload A (500m CPU, 512Mi RAM baseline)
│   ├── worker-deployment.yaml        ← Workload B (1 CPU, 1Gi RAM baseline)
│   ├── report-deployment.yaml        ← Workload C (2 CPU, 2Gi RAM) ← primary target
│   ├── services.yaml                 ← ClusterIP services
│   └── optimized-deployments.yaml   ← Right-sized resources (applied post-baseline)
│
├── monitoring/
│   ├── prometheus/
│   │   └── values.yaml              ← Helm values for kube-prometheus-stack
│   └── grafana/
│       ├── dashboard.json           ← Full Grafana dashboard (import via UI)
│       └── dashboard-configmap.yaml
│
├── opencost/
│   ├── values.yaml                  ← Helm values for OpenCost
│   └── opencost-manifests.yaml      ← Direct kubectl install (no Helm needed)
│
├── load-testing/
│   └── load-test.sh                 ← HTTP load generator (low/medium/high)
│
├── scripts/
│   ├── setup.sh                     ← Master one-shot setup script
│   ├── collect-baseline.sh          ← Collect metrics BEFORE optimization
│   └── collect-after.sh             ← Collect metrics AFTER + comparison
│
├── results/
│   ├── baseline.csv                 ← Captured baseline measurements
│   ├── optimized.csv                ← Captured post-optimization measurements
│   └── comparison.txt               ← Full before/after summary with cost data
│
└── screenshots/                     ← Grafana & OpenCost demo screenshots
```

---

## Baseline Workloads (Before Optimization)

| Workload | CPU Request | Memory Request | CPU Limit | Memory Limit | Actual CPU Used | Actual Mem Used |
|----------|------------|----------------|-----------|--------------|-----------------|-----------------|
| `api-service` (×2) | 500m | 512Mi | 1000m | 1Gi | **1m** | **12Mi** |
| `background-worker` | 1000m | 1Gi | 2000m | 2Gi | **82m** | **~1Mi** |
| `report-service` ⚠️ | **2000m** | **2Gi** | 4000m | 4Gi | **1m** | **12Mi** |
| **TOTAL** | **3500m** | **3.5Gi** | 7000m | 7Gi | — | — |

> ⚠️ `report-service` requests **2000m CPU** but uses only **1m** — a 99.95% waste. This is the primary optimization target.

---

## Optimized Workloads (After Optimization)

Values derived using formula: **`request = peak_observed × 1.3`**, **`limit = request × 2`**

| Workload | CPU Request | Memory Request | CPU Limit | Memory Limit |
|----------|------------|----------------|-----------|--------------|
| `api-service` (×2) | **5m** | **20Mi** | 10m | 40Mi |
| `background-worker` | **110m** | **32Mi** | 220m | 64Mi |
| `report-service` ✅ | **5m** | **20Mi** | 10m | 40Mi |
| **TOTAL** | **120m** | **~72Mi** | 240m | ~144Mi |

---

## Key Findings

```
CPU Requested:   3500m → 120m     ↓ 96.6%
Memory Requested: 3.5Gi → 72Mi   ↓ 98.0%
Namespace Cost:  $0.1195 → $0.0006/hr  ↓ 99.5%
Efficiency:      3.5%   → 8.7%   ↑ +5.2pp
```

---

## Quick Start (WSL2)

```bash
# 1. Clone the repo
git clone https://github.com/shlokapol2005/k8s-cost-optimization.git
cd k8s-cost-optimization

# 2. Start Minikube (6 CPUs, 8 Gi RAM)
minikube start --cpus=6 --memory=8192 --driver=docker
minikube addons enable metrics-server

# 3. Deploy baseline workloads
kubectl apply -f k8s/

# 4. Install monitoring + OpenCost
bash scripts/setup.sh

# 5. Run load test and collect baseline
bash load-testing/load-test.sh medium
bash scripts/collect-baseline.sh

# 6. Apply optimized config (fill values from kubectl top first)
kubectl apply -f k8s/optimized-deployments.yaml

# 7. Collect after data
bash load-testing/load-test.sh medium
bash scripts/collect-after.sh
cat results/comparison.txt
```

> See [SETUP_GUIDE.md](SETUP_GUIDE.md) for the full step-by-step walkthrough.

---

## Grafana Dashboard

1. Port-forward: `kubectl port-forward svc/kube-prom-stack-grafana 3000:80 -n monitoring`
2. Open: `http://localhost:3000` → Login: `admin / devops-demo-2024`
3. **Dashboards → Cost Optimization → K8s Cost & Resource Optimization**

Dashboard sections:
- **Resource Overview** — CPU & Memory timeseries per pod
- **Requests vs Actual Usage** — Bar charts showing the over-provisioning gap
- **OpenCost Cost Panels** — Estimated cost per pod, CPU vs Memory split
- **Efficiency Gauges** — Red/Yellow/Green ratio of used/requested

---

## OpenCost

```bash
# Port-forward
kubectl port-forward svc/opencost -n opencost 9090:9090 9003:9003

# UI  → http://localhost:9090
# API → http://localhost:9003

# Query cost-demo namespace cost
curl -s "http://localhost:9003/allocation?window=1h&aggregate=namespace" | \
  python3 -c "
import json,sys; data=json.load(sys.stdin)
for w in data.get('data',[]): 
  if 'cost-demo' in w: print(f'Total: \${w[\"cost-demo\"].get(\"totalCost\",0):.6f}/hr')
"
```

---

## GitHub Actions CI

The pipeline validates on every push:
1. ✅ Kubernetes YAML manifests (`kubectl --dry-run`)
2. ✅ YAML syntax (`yamllint`)
3. ✅ Shell scripts (`shellcheck`)
4. ✅ Grafana dashboard JSON (Python syntax check)

> Deployment is intentionally **local only** — CI validates configuration, Minikube runs the actual demo.

---

## Conclusion

This project demonstrates a complete **measure → optimize → verify** workflow:

1. Deployed 3 intentionally over-provisioned workloads on Minikube
2. Instrumented with Prometheus + Grafana for real-time visibility
3. Used OpenCost to quantify estimated resource allocation cost
4. Identified over-provisioning via `kubectl top` under realistic load
5. Right-sized resource requests using `peak_usage × 1.3` formula
6. Measured **96.6% CPU reduction**, **98% memory reduction**, **99.5% cost reduction**

> The result validates that Kubernetes resource right-sizing based on empirical utilization data significantly reduces estimated infrastructure cost with no impact on application availability.
