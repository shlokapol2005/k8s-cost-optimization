# Kubernetes Cost Monitoring & Resource Optimization

> **Topic:** Kubernetes Cost Monitoring and Resource Optimization using OpenCost + Grafana + Prometheus on Minikube
>
> **Research Question:** How can Kubernetes resource requests and limits be right-sized to reduce estimated infrastructure cost while maintaining application performance?

[![CI](https://github.com/shlokapol2005/k8s-cost-optimization/actions/workflows/ci.yaml/badge.svg)](https://github.com/shlokapol2005/k8s-cost-optimization/actions/workflows/ci.yaml)

---

## 📋 Table of Contents

1. [Project Overview](#-project-overview)
2. [The Problem](#-the-problem--kubernetes-over-provisioning)
3. [Tools & Technologies](#-tools--technologies)
4. [Architecture](#-architecture)
5. [Project Phases](#-project-phases)
6. [Experiment Methodology](#-experiment-methodology)
7. [Real Results](#-real-results-measured-live)
8. [Repository Structure](#-repository-structure)
9. [How to Run](#-how-to-run)
10. [Conclusion](#-conclusion)

---

## 📌 Project Overview

This project implements a complete **Kubernetes resource cost monitoring and optimization pipeline** on a local Minikube cluster. It follows a scientific **Baseline → Measure → Optimize → Verify** workflow to demonstrate how Kubernetes workloads can be right-sized based on real utilization data.

Three intentionally over-provisioned microservices are deployed, load-tested, and monitored using industry-standard tools (Prometheus, Grafana, OpenCost). After collecting baseline metrics, resource requests are reduced to match actual usage. The before-and-after results are compared using OpenCost's estimated cost allocation model.

> **Important Note on Cost Figures:** Since the experiment is conducted on a local Minikube cluster rather than a cloud provider, OpenCost values represent *estimated* resource allocation costs based on a configured pricing model (approximate AWS us-east-1 t3.medium rates). They should not be interpreted as an actual cloud billing amount.

---

## 🔴 The Problem — Kubernetes Over-Provisioning

In Kubernetes, developers set `resource requests` (guaranteed CPU/memory) and `limits` (maximum allowed). A common mistake is to over-provision — setting requests far higher than what the workload actually needs.

**Why this is a problem:**
- The Kubernetes scheduler **reserves** the requested resources on a node, even if the pod never uses them
- Over-provisioned pods prevent other pods from being scheduled on the same node
- In cloud environments, you pay for **reserved node capacity**, not just actual usage
- A cluster running at 5% efficiency wastes 95% of its compute budget

**This project proves the problem exists and fixes it with real data.**

### Baseline Over-Provisioning (Intentional)

| Workload | CPU Requested | CPU Actually Used | Waste |
|----------|--------------|-------------------|-------|
| `api-service` | 500m | **1m** | 99.8% |
| `background-worker` | 1000m | **82m** | 91.8% |
| `report-service` ⚠️ | **2000m** | **1m** | 99.95% |
| **Total** | **3500m** | **~84m** | **~97.6%** |

---

## 🛠 Tools & Technologies

| Tool | Role in Project |
|------|----------------|
| **Kubernetes / Minikube** | Local Kubernetes cluster for running all workloads |
| **kubectl** | CLI to deploy, inspect, and manage Kubernetes resources |
| **Helm** | Package manager used to install Prometheus stack and OpenCost |
| **Prometheus** | Time-series database that scrapes and stores all cluster metrics |
| **Grafana** | Visualization layer — dashboards for CPU, memory, efficiency, cost |
| **OpenCost** | Cost allocation engine — estimates $/hr per namespace, pod, workload |
| **Docker Desktop + WSL2** | Container runtime and Linux environment on Windows |
| **GitHub Actions** | CI pipeline — validates YAML manifests and shell scripts on every push |

---

## 🏗 Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                        GitHub                                │
│   Push → GitHub Actions CI                                   │
│           ├── kubectl --dry-run  (validate k8s YAMLs)        │
│           ├── yamllint           (YAML syntax check)         │
│           ├── shellcheck         (shell script linting)      │
│           └── python json.load   (Grafana dashboard check)   │
└──────────────────────────┬───────────────────────────────────┘
                           │
                    ┌──────▼──────┐
                    │  Minikube   │  ← 6 CPU, 8GB RAM
                    │  Kubernetes │
                    └──────┬──────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
   ┌─────────────┐  ┌────────────┐  ┌─────────────┐
   │ api-service │  │  worker    │  │   report    │
   │  (nginx)   │  │  (shell)   │  │  (nginx)   │
   │  2 replicas│  │  1 replica │  │  1 replica  │
   └──────┬──────┘  └─────┬──────┘  └─────────────┘
          │    polls /work │
          └────────────────┘
          ↑
   ┌──────────────┐
   │ Load Tester  │  ← bash load-test.sh (curl workers)
   │ (curl loops) │
   └──────────────┘
          │
          ▼
   ┌────────────────────────────────────────┐
   │              Prometheus                │
   │  Scrapes: kube-state-metrics,          │
   │  node-exporter, metrics-server,        │
   │  OpenCost exporter                     │
   └──────────────────┬─────────────────────┘
                      │
          ┌───────────┴───────────┐
          ▼                       ▼
   ┌─────────────┐        ┌─────────────┐
   │   Grafana   │        │  OpenCost   │
   │  Dashboard  │        │  Cost API   │
   └─────────────┘        └─────────────┘
```

### Load Chain
The load test sends HTTP requests to `api-service`. The `background-worker` continuously polls the `/work` endpoint on `api-service`, triggering CPU-heavy arithmetic. This creates a **real, measurable load chain** — external traffic directly drives the worker's CPU utilization, making the experiment scientifically valid.

---

## 📐 Project Phases

### Phase 1 — Environment Setup
Install WSL2 + Ubuntu, Docker Desktop, kubectl, Minikube, and Helm. Start Minikube with 6 CPUs and 8GB RAM to accommodate the full stack.

### Phase 2 — Deploy Baseline Workloads
Deploy 3 workloads in the `cost-demo` namespace with **intentionally over-provisioned** resource requests. Each workload is a real nginx-based HTTP service:
- `api-service` — handles incoming requests, exposes `/work` endpoint
- `background-worker` — polls api-service, simulates background processing load
- `report-service` — the most over-provisioned workload (2000m CPU for 1m actual usage)

### Phase 3 — Install Monitoring Stack
Install `kube-prometheus-stack` via Helm. This deploys:
- **Prometheus** — scrapes all cluster metrics every 15s
- **Grafana** — pre-configured with custom dashboards
- **kube-state-metrics** — exposes Kubernetes object metrics
- **node-exporter** — exposes node-level hardware metrics

### Phase 4 — Install OpenCost
Deploy OpenCost (cost allocation engine) with a custom pricing model matching approximate AWS rates. OpenCost reads Prometheus metrics and converts CPU/memory usage into estimated $/hr costs per namespace and pod.

### Phase 5 — Run Load Test & Collect Baseline
Generate realistic HTTP traffic for 120 seconds using a multi-worker curl-based load tester. While load runs, `kubectl top` captures live CPU/memory usage. The `collect-baseline.sh` script saves these measurements to `results/baseline.csv`.

### Phase 6 — Analyze & Determine Optimized Values
Using the formula `request = peak_observed_usage × 1.3` (30% headroom):

| Workload | Peak CPU (kubectl top) | Optimized Request |
|----------|----------------------|-------------------|
| api-service | 1m | 5m (safe minimum) |
| background-worker | 82m | 110m |
| report-service | 1m | 5m (safe minimum) |

### Phase 7 — Apply Optimized Configuration
Apply `k8s/optimized-deployments.yaml` with the new right-sized values. Kubernetes performs a rolling update — zero downtime. Pods restart with lower resource requests.

### Phase 8 — Verify & Collect After Metrics
Run the same load test again under optimized configuration. `collect-after.sh` captures the new metrics and produces `results/comparison.txt` — the full before/after report.

### Phase 9 — Push to GitHub
All configurations, scripts, and results are version-controlled. GitHub Actions CI automatically validates every manifest on push.

---

## 🔬 Experiment Methodology

The experiment follows the scientific method:

1. **Hypothesis:** Kubernetes workloads in this cluster have resource requests significantly larger than actual usage, and reducing them will lower the estimated cost without impacting availability.

2. **Baseline measurement:** Deploy workloads → wait for metrics-server warmup → run load test → record `kubectl top` values and OpenCost cost.

3. **Intervention:** Apply optimized resource requests derived from `peak × 1.3` formula.

4. **Post-intervention measurement:** Run identical load test → record same metrics.

5. **Comparison:** Compute delta between baseline.csv and optimized.csv. Verify pods remain `Running` throughout.

6. **Control:** Same load test (medium, 120s, 5 workers) used in both phases. Same namespace, same workloads.

---

## 📊 Real Results (Measured Live)

### Resource Requests — Before vs After

| Workload | CPU Before | CPU After | Mem Before | Mem After |
|----------|-----------|-----------|------------|-----------|
| `api-service` (×2) | 500m | **5m** | 512Mi | **20Mi** |
| `background-worker` | 1000m | **110m** | 1Gi | **32Mi** |
| `report-service` ⭐ | **2000m** | **5m** | **2Gi** | **20Mi** |
| **TOTAL** | **3500m** | **120m** | **~3.5Gi** | **~72Mi** |
| **Reduction** | | **↓ 96.6%** | | **↓ 98%** |

### OpenCost Estimated Cost — `cost-demo` Namespace

| Cost Component | BEFORE | AFTER | Reduction |
|----------------|--------|-------|-----------|
| CPU Cost | $0.105370/hr | $0.000530/hr | **↓ 99.5%** |
| Memory Cost | $0.014120/hr | $0.000050/hr | **↓ 99.6%** |
| **Total Cost** | **$0.119490/hr** | **$0.000580/hr** | **↓ 99.5%** |

### Efficiency

| Metric | Before | After |
|--------|--------|-------|
| Cluster Efficiency (OpenCost) | 3.5% | 8.7% |

### Annualised Saving Estimate *(illustrative — scale for actual node counts)*

| Period | Saving |
|--------|--------|
| Per hour | $0.1189 |
| Per day | $2.85 |
| Per month | $86.80 |
| Per year | $1,041.85 |

---

## 📁 Repository Structure

```
k8s-cost-optimization/
│
├── .github/workflows/
│   └── ci.yaml                    ← CI: validates YAMLs, shell scripts, JSON
│
├── k8s/
│   ├── namespace.yaml             ← Creates 'cost-demo' namespace
│   ├── api-deployment.yaml        ← api-service (nginx + /work endpoint)
│   ├── worker-deployment.yaml     ← background-worker (polls api, does CPU work)
│   ├── report-deployment.yaml     ← report-service (intentionally 2000m CPU)
│   ├── services.yaml              ← ClusterIP services for all 3 workloads
│   └── optimized-deployments.yaml ← Right-sized resources (applied post-baseline)
│
├── monitoring/
│   ├── prometheus/values.yaml     ← Helm values: scrape intervals, retention
│   └── grafana/
│       ├── dashboard.json         ← Custom dashboard (Resource, Cost, Efficiency)
│       └── dashboard-configmap.yaml
│
├── opencost/
│   ├── values.yaml                ← Helm values with custom pricing model
│   └── opencost-manifests.yaml   ← Direct kubectl install (no Helm needed)
│
├── load-testing/
│   └── load-test.sh              ← Multi-worker curl load generator (low/med/high)
│
├── scripts/
│   ├── setup.sh                  ← One-shot: Minikube + workloads + monitoring
│   ├── collect-baseline.sh       ← Saves baseline metrics to results/baseline.csv
│   └── collect-after.sh         ← Saves optimized metrics + prints comparison
│
├── results/
│   ├── baseline.csv              ← Captured baseline measurements
│   ├── optimized.csv             ← Captured post-optimization measurements
│   └── comparison.txt            ← Full before/after report with cost figures
│
├── screenshots/                  ← Grafana & OpenCost screenshots (before/after)
├── SETUP_GUIDE.md               ← Complete step-by-step setup walkthrough
└── README.md                    ← This file
```

---

## ▶ How to Run

> Prerequisites: WSL2 + Ubuntu, Docker Desktop (with WSL2 integration enabled), internet connection.

### Step 1 — Install tools (inside WSL2)
```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Step 2 — Clone and start
```bash
git clone https://github.com/shlokapol2005/k8s-cost-optimization.git
cd k8s-cost-optimization
bash scripts/setup.sh
```

### Step 3 — Access dashboards
```bash
# Grafana
kubectl port-forward svc/kube-prom-stack-grafana 3000:80 -n monitoring
# Open: http://localhost:3000  |  Login: admin / devops-demo-2024

# OpenCost UI + API
kubectl port-forward svc/opencost -n opencost 9090:9090 9003:9003
# UI:  http://localhost:9090
# API: http://localhost:9003
```

### Step 4 — Run experiment
```bash
# Collect baseline (BEFORE)
bash load-testing/load-test.sh medium
bash scripts/collect-baseline.sh

# Apply optimized config (fill values from kubectl top output)
kubectl apply -f k8s/optimized-deployments.yaml

# Collect after (AFTER)
bash load-testing/load-test.sh medium
bash scripts/collect-after.sh

# View results
cat results/comparison.txt
```

> See [SETUP_GUIDE.md](SETUP_GUIDE.md) for the full detailed walkthrough including troubleshooting.

---

## ✅ GitHub Actions CI

On every `git push`, the CI pipeline automatically:

| Check | Tool | What it validates |
|-------|------|-------------------|
| Kubernetes YAML | `kubectl --dry-run` | All manifests are valid K8s objects |
| YAML syntax | `yamllint` | No formatting or indentation errors |
| Shell scripts | `shellcheck` | No bash anti-patterns or bugs |
| Grafana JSON | `python3 json.load` | Dashboard JSON is parseable |

---

## 🏁 Conclusion

This project demonstrates that Kubernetes resource right-sizing based on empirical utilization data produces dramatic cost savings:

- **96.6% reduction** in CPU requests (3500m → 120m)
- **98% reduction** in memory requests (3.5Gi → 72Mi)
- **99.5% reduction** in estimated namespace cost ($0.1195 → $0.0006/hr)
- **Zero downtime** — all pods remained `Running` throughout the optimization

The key insight is that Kubernetes reservations (requests) — not actual usage — drive cloud infrastructure cost. A workload using 1m CPU but requesting 2000m costs the same as a workload actually using 2000m. Right-sizing requests to match real utilization is therefore the highest-impact, lowest-risk optimization available in any Kubernetes environment.

> **Methodology note:** Optimized values were set at `peak_observed × 1.3` (30% headroom above peak observed usage), ensuring the application has capacity for traffic spikes while eliminating the 97%+ waste seen in the baseline configuration.
