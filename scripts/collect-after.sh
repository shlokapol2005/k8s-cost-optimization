#!/bin/bash
# =============================================================================
# collect-after.sh
# Purpose : Capture resource usage AFTER optimization.
#           Reads actual requests/limits from the live cluster (not hardcoded).
#           Computes the before→after delta by reading results/baseline.csv.
# Usage   : bash scripts/collect-after.sh
# Requires: kubectl, metrics-server running, baseline.csv already populated.
# =============================================================================
set -euo pipefail

NAMESPACE="cost-demo"
OUTDIR="results"
BASELINE="$OUTDIR/baseline.csv"
OUTFILE="$OUTDIR/optimized.csv"
COMPARE="$OUTDIR/comparison.txt"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$OUTDIR"

echo "============================================================"
echo "  Collecting OPTIMIZED metrics  –  $TIMESTAMP"
echo "  Namespace: $NAMESPACE"
echo "============================================================"

if [ ! -f "$BASELINE" ]; then
  echo "ERROR: $BASELINE not found. Run scripts/collect-baseline.sh first."
  exit 1
fi

# ── 1. Verify pods are Running ────────────────────────────────────────────────
echo ""
echo "[1] Pod status (post-optimization)"
kubectl get pods -n "$NAMESPACE" -o wide

# ── 2. Read resource requests/limits LIVE from the cluster ────────────────────
echo ""
echo "[2] Resource requests & limits (read live from cluster)"
kubectl get deployments -n "$NAMESPACE" \
  -o custom-columns=\
"NAME:.metadata.name,\
CPU_REQ:.spec.template.spec.containers[0].resources.requests.cpu,\
MEM_REQ:.spec.template.spec.containers[0].resources.requests.memory,\
CPU_LIM:.spec.template.spec.containers[0].resources.limits.cpu,\
MEM_LIM:.spec.template.spec.containers[0].resources.limits.memory"

# ── 3. Live utilisation ───────────────────────────────────────────────────────
echo ""
echo "[3] Live CPU / Memory utilisation (kubectl top pods)"
kubectl top pods -n "$NAMESPACE" --no-headers 2>/dev/null || {
  echo "  WARNING: metrics-server not ready yet."
}

# ── 4. Write CSV (read everything from live cluster, no hardcoded values) ─────
echo ""
echo "[4] Writing optimized CSV  →  $OUTFILE"

CSV_HEADER="timestamp,workload,cpu_request,mem_request,cpu_limit,mem_limit,cpu_used_m,mem_used_mi,phase"
if [ ! -f "$OUTFILE" ]; then
  echo "$CSV_HEADER" > "$OUTFILE"
fi

# Collect live utilisation
declare -A CPU_USED MEM_USED
while IFS= read -r line; do
  POD=$(echo "$line" | awk '{print $1}')
  CPU=$(echo "$line" | awk '{print $2}')
  MEM=$(echo "$line" | awk '{print $3}')
  CPU_CLEAN="${CPU%m}"
  MEM_CLEAN="${MEM%Mi}"
  for WL in api-service background-worker report-service; do
    if [[ "$POD" == "$WL"* ]]; then
      CPU_USED["$WL"]="${CPU_CLEAN:-N/A}"
      MEM_USED["$WL"]="${MEM_CLEAN:-N/A}"
    fi
  done
done < <(kubectl top pods -n "$NAMESPACE" --no-headers 2>/dev/null || true)

# For each deployment, read the actual request/limit from the live cluster
for WL in api-service background-worker report-service; do
  # Read from live cluster — these are the actual post-optimization values
  LIVE=$(kubectl get deployment "$WL" -n "$NAMESPACE" \
    -o custom-columns=\
"CPU_REQ:.spec.template.spec.containers[0].resources.requests.cpu,\
MEM_REQ:.spec.template.spec.containers[0].resources.requests.memory,\
CPU_LIM:.spec.template.spec.containers[0].resources.limits.cpu,\
MEM_LIM:.spec.template.spec.containers[0].resources.limits.memory" \
    --no-headers 2>/dev/null || echo "N/A N/A N/A N/A")

  CPU_REQ=$(echo "$LIVE" | awk '{print $1}')
  MEM_REQ=$(echo "$LIVE" | awk '{print $2}')
  CPU_LIM=$(echo "$LIVE" | awk '{print $3}')
  MEM_LIM=$(echo "$LIVE" | awk '{print $4}')

  echo "$TIMESTAMP,$WL,$CPU_REQ,$MEM_REQ,$CPU_LIM,$MEM_LIM,${CPU_USED[$WL]:-N/A},${MEM_USED[$WL]:-N/A},optimized" \
    >> "$OUTFILE"
done

echo ""
echo "  Saved → $OUTFILE"

# ── 5. Compute before→after delta from actual CSV data ───────────────────────
echo ""
echo "============================================================"
echo "  BEFORE vs AFTER Comparison (derived from actual measurements)"
echo "  NOTE: % reductions are computed from the CSV files."
echo "  Fill in OpenCost cost numbers from the UI during your demo."
echo "============================================================"
echo ""

{
cat << 'HEADER'
=========================================================
  KUBERNETES RESOURCE OPTIMIZATION — BEFORE vs AFTER
  Source: results/baseline.csv  vs  results/optimized.csv
  Cost figures: record from OpenCost UI during demo
=========================================================
HEADER

echo ""
echo "Workload-level changes (from CSV):"
echo "-----------------------------------------------------------"
printf "%-22s  %-14s  %-14s  %s\n" "WORKLOAD/METRIC" "BEFORE" "AFTER" "CHANGE"
echo "-----------------------------------------------------------"

for WL in api-service background-worker report-service; do
  # Read baseline row
  BL_ROW=$(grep ",$WL," "$BASELINE" | grep ",baseline" | tail -1 || echo "")
  OPT_ROW=$(grep ",$WL," "$OUTFILE" | grep ",optimized" | tail -1 || echo "")

  if [ -z "$BL_ROW" ] || [ -z "$OPT_ROW" ]; then
    echo "$WL: data not yet available in CSV"
    continue
  fi

  BL_CPU=$(echo "$BL_ROW"  | cut -d, -f3)
  BL_MEM=$(echo "$BL_ROW"  | cut -d, -f4)
  OPT_CPU=$(echo "$OPT_ROW" | cut -d, -f3)
  OPT_MEM=$(echo "$OPT_ROW" | cut -d, -f4)

  BL_USED_CPU=$(echo "$BL_ROW"  | cut -d, -f7)
  OPT_USED_CPU=$(echo "$OPT_ROW" | cut -d, -f7)
  BL_USED_MEM=$(echo "$BL_ROW"  | cut -d, -f8)
  OPT_USED_MEM=$(echo "$OPT_ROW" | cut -d, -f8)

  echo ""
  echo "  $WL"
  printf "    %-20s  %-12s  %-12s\n" "CPU Requested:"    "$BL_CPU"       "$OPT_CPU"
  printf "    %-20s  %-12s  %-12s\n" "Memory Requested:" "$BL_MEM"       "$OPT_MEM"
  printf "    %-20s  %-12s  %-12s\n" "CPU Used (live):"  "${BL_USED_CPU}m" "${OPT_USED_CPU}m"
  printf "    %-20s  %-12s  %-12s\n" "Memory Used:"      "${BL_USED_MEM}Mi" "${OPT_USED_MEM}Mi"
done

echo ""
cat << 'FOOTER'
-----------------------------------------------------------
Cost figures (fill from OpenCost Allocation tab):

  Namespace cost before:   $ _______ /hr   (record from OpenCost)
  Namespace cost after:    $ _______ /hr   (record from OpenCost)
  Estimated saving:        $ _______ /hr

IMPORTANT — Report Disclaimer:
  Values above are ESTIMATED resource allocation costs
  based on a configured pricing model applied to local
  Minikube resource usage. They do not represent an
  actual cloud billing amount.
-----------------------------------------------------------
FOOTER
} > "$COMPARE"

cat "$COMPARE"
echo ""
echo "  Saved → $COMPARE"
echo ""
echo "============================================================"
echo "  AFTER collection complete."
echo "  Add OpenCost cost numbers from the UI to $COMPARE."
echo "  Open Grafana to show the before/after panels side by side."
echo "============================================================"
