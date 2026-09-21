#!/bin/bash
# =============================================================================
# collect-baseline.sh
# Purpose : Capture resource usage BEFORE optimization and save to CSV.
# Usage   : bash scripts/collect-baseline.sh
# Requires: kubectl, metrics-server running in the cluster.
# =============================================================================
set -euo pipefail

NAMESPACE="cost-demo"
OUTDIR="results"
OUTFILE="$OUTDIR/baseline.csv"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$OUTDIR"

echo "============================================================"
echo "  Collecting BASELINE metrics  –  $TIMESTAMP"
echo "  Namespace: $NAMESPACE"
echo "============================================================"

# ── 1. Verify pods are Running ────────────────────────────────────────────────
echo ""
echo "[1] Pod status"
kubectl get pods -n "$NAMESPACE" -o wide

# ── 2. Resource requests/limits from deployment specs ─────────────────────────
echo ""
echo "[2] Resource requests & limits (from deployment specs)"
kubectl get deployments -n "$NAMESPACE" \
  -o custom-columns=\
"NAME:.metadata.name,\
CPU_REQ:.spec.template.spec.containers[0].resources.requests.cpu,\
MEM_REQ:.spec.template.spec.containers[0].resources.requests.memory,\
CPU_LIM:.spec.template.spec.containers[0].resources.limits.cpu,\
MEM_LIM:.spec.template.spec.containers[0].resources.limits.memory"

# ── 3. Live utilisation via metrics-server ────────────────────────────────────
echo ""
echo "[3] Live CPU / Memory utilisation (kubectl top pods)"
kubectl top pods -n "$NAMESPACE" --no-headers 2>/dev/null || {
  echo "  WARNING: metrics-server not ready yet. Skipping live metrics."
  echo "  Run: minikube addons enable metrics-server  (if not already done)"
}

# ── 4. Write CSV ──────────────────────────────────────────────────────────────
echo ""
echo "[4] Writing baseline CSV  →  $OUTFILE"

CSV_HEADER="timestamp,workload,cpu_request,mem_request,cpu_limit,mem_limit,cpu_used_m,mem_used_mi,phase"

if [ ! -f "$OUTFILE" ]; then
  echo "$CSV_HEADER" > "$OUTFILE"
fi

# Fetch live top data into associative array (requires bash ≥4)
declare -A CPU_USED MEM_USED

while IFS= read -r line; do
  POD=$(echo "$line" | awk '{print $1}')
  CPU=$(echo "$line" | awk '{print $2}')
  MEM=$(echo "$line" | awk '{print $3}')

  # Strip trailing 'm' from CPU and 'Mi' from MEM for storage
  CPU_CLEAN="${CPU%m}"
  MEM_CLEAN="${MEM%Mi}"

  # Map pod prefix to workload name
  for WL in api-service background-worker report-service; do
    if [[ "$POD" == "$WL"* ]]; then
      CPU_USED["$WL"]="${CPU_CLEAN:-N/A}"
      MEM_USED["$WL"]="${MEM_CLEAN:-N/A}"
    fi
  done
done < <(kubectl top pods -n "$NAMESPACE" --no-headers 2>/dev/null || true)

# Deployment request/limit values (baseline)
declare -A CPU_REQ=( ["api-service"]="500m" ["background-worker"]="1000m" ["report-service"]="2000m" )
declare -A MEM_REQ=( ["api-service"]="512Mi" ["background-worker"]="1Gi"   ["report-service"]="2Gi"   )
declare -A CPU_LIM=( ["api-service"]="1000m" ["background-worker"]="2000m" ["report-service"]="4000m" )
declare -A MEM_LIM=( ["api-service"]="1Gi"   ["background-worker"]="2Gi"   ["report-service"]="4Gi"   )

for WL in api-service background-worker report-service; do
  echo "$TIMESTAMP,$WL,${CPU_REQ[$WL]},${MEM_REQ[$WL]},${CPU_LIM[$WL]},${MEM_LIM[$WL]},${CPU_USED[$WL]:-N/A},${MEM_USED[$WL]:-N/A},baseline" \
    >> "$OUTFILE"
done

echo ""
echo "  Saved → $OUTFILE"
cat "$OUTFILE"
echo ""
echo "============================================================"
echo "  BASELINE collection complete."
echo "  Next step: run the load test, then apply optimizations."
echo "============================================================"
