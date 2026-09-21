#!/bin/bash
# =============================================================================
# load-test.sh
# Purpose : Generate HTTP traffic against api-service and report-service
#           so that kubectl top shows realistic CPU/memory usage.
# Usage   :
#   LOW load  : bash load-testing/load-test.sh low
#   MEDIUM    : bash load-testing/load-test.sh medium
#   HIGH      : bash load-testing/load-test.sh high
# Requires: kubectl (to port-forward), curl
# =============================================================================
set -euo pipefail

NAMESPACE="cost-demo"
LEVEL="${1:-medium}"          # low | medium | high
DURATION_SECS=120             # how long to run the load
API_PORT=8080
REPORT_PORT=8081

echo "============================================================"
echo "  Load Test  –  level=$LEVEL  duration=${DURATION_SECS}s"
echo "============================================================"

# ── Start port-forwards in background ────────────────────────────────────────
echo "[*] Starting port-forwards …"
kubectl port-forward svc/api-service    -n "$NAMESPACE" "${API_PORT}:80"    &>/dev/null &
PF_API=$!
kubectl port-forward svc/report-service -n "$NAMESPACE" "${REPORT_PORT}:80" &>/dev/null &
PF_REPORT=$!

cleanup() {
  echo ""
  echo "[*] Stopping port-forwards …"
  kill "$PF_API"    2>/dev/null || true
  kill "$PF_REPORT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

sleep 3   # wait for port-forwards to establish

# ── Concurrency per load level ────────────────────────────────────────────────
case "$LEVEL" in
  low)    CONCURRENCY=2  ; SLEEP=1.0 ;;
  medium) CONCURRENCY=5  ; SLEEP=0.5 ;;
  high)   CONCURRENCY=15 ; SLEEP=0.1 ;;
  *)
    echo "Unknown level '$LEVEL'. Use: low | medium | high"
    exit 1 ;;
esac

echo "[*] Sending $CONCURRENCY concurrent workers for ${DURATION_SECS}s …"
echo "    Targets: http://localhost:$API_PORT  &  http://localhost:$REPORT_PORT"
echo ""

END_TIME=$(( $(date +%s) + DURATION_SECS ))

# Worker function
send_requests() {
  local TARGET=$1
  local SLEEP_S=$2
  while [ "$(date +%s)" -lt "$END_TIME" ]; do
    curl -sf "$TARGET" -o /dev/null || true
    sleep "$SLEEP_S" || true
  done
}

# Launch workers for api-service
for i in $(seq 1 "$CONCURRENCY"); do
  send_requests "http://localhost:$API_PORT/" "$SLEEP" &
done

# Launch workers for report-service (half concurrency)
HALF_CONC=$(( CONCURRENCY / 2 + 1 ))
for i in $(seq 1 "$HALF_CONC"); do
  send_requests "http://localhost:$REPORT_PORT/" "$SLEEP" &
done

# Progress bar
ELAPSED=0
while [ "$(date +%s)" -lt "$END_TIME" ]; do
  printf "\r  Progress: %3d / %d s" "$ELAPSED" "$DURATION_SECS"
  sleep 5
  ELAPSED=$(( ELAPSED + 5 ))
done

wait
echo ""
echo ""
echo "============================================================"
echo "  Load test finished."
echo "  Run: kubectl top pods -n $NAMESPACE"
echo "  Then: bash scripts/collect-baseline.sh  (or collect-after.sh)"
echo "============================================================"
