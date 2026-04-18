#!/usr/bin/env bash
#
# run_experiment5.sh — single-region CAP experiment baseline (Run A).
# Fires a fixed-payload load at the west ALB for 30s, fully headless,
# and writes CSV + HTML reports to ./results/.

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
ALB_DNS="trading-risk-monitor-alb-703965592.us-west-2.elb.amazonaws.com"
HOST="http://${ALB_DNS}"
LOCUST_FILE="locust/region_test.py"
USERS=100
SPAWN_RATE=100
RUN_TIME="30s"
RESULTS_DIR="results"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_RESET=$'\e[0m'
    C_BOLD=$'\e[1m'
    C_GREEN=$'\e[32m'
    C_YELLOW=$'\e[33m'
    C_CYAN=$'\e[36m'
    C_RED=$'\e[31m'
else
    C_RESET="" C_BOLD="" C_GREEN="" C_YELLOW="" C_CYAN="" C_RED=""
fi

info()    { echo "${C_CYAN}[info]${C_RESET}  $*"; }
success() { echo "${C_GREEN}[ok]${C_RESET}    $*"; }
warn()    { echo "${C_YELLOW}[warn]${C_RESET}  $*"; }
err()     { echo "${C_RED}[error]${C_RESET} $*" >&2; }

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
mkdir -p "$RESULTS_DIR"

# ---------------------------------------------------------------------------
# Pre-flight — locust on PATH
# ---------------------------------------------------------------------------
info "Pre-flight checks..."
if ! command -v locust >/dev/null 2>&1; then
    err "locust is not installed or not on PATH."
    echo
    echo "  Install with:"
    echo "    ${C_CYAN}pip install -r locust/requirements.txt${C_RESET}"
    echo "  or:"
    echo "    ${C_CYAN}pip install locust requests${C_RESET}"
    echo
    exit 1
fi
success "locust is installed ($(locust --version 2>&1 | head -1))"

# ---------------------------------------------------------------------------
# Pre-flight — ALB reachability
# ---------------------------------------------------------------------------
info "Testing ALB health at ${C_CYAN}${HOST}/transaction${C_RESET}..."
healthcheck_payload='{"user_id":"healthcheck","amount":1,"currency":"USD","transaction_type":"purchase"}'

set +e
healthcheck_status=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 10 \
    -X POST "${HOST}/transaction" \
    -H "Content-Type: application/json" \
    -d "$healthcheck_payload")
curl_exit=$?
set -e

if [[ $curl_exit -ne 0 ]]; then
    err "Could not reach ALB at ${HOST} (curl exit ${curl_exit})."
    err "Check the ALB DNS, the ECS transaction service, and your network."
    exit 1
fi

if [[ "$healthcheck_status" != "202" ]]; then
    warn "ALB responded with HTTP ${healthcheck_status} (expected 202). Continuing anyway."
else
    success "ALB healthy — got HTTP 202 Accepted"
fi

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
echo
echo "${C_GREEN}${C_BOLD}============================================================${C_RESET}"
echo "${C_GREEN}${C_BOLD}  CAP EXPERIMENT — RUN A (single-region baseline)${C_RESET}"
echo "${C_GREEN}${C_BOLD}============================================================${C_RESET}"
info "host        = ${C_CYAN}${HOST}${C_RESET}"
info "locust file = ${LOCUST_FILE}"
info "users       = ${USERS}"
info "spawn rate  = ${SPAWN_RATE}"
info "run time    = ${RUN_TIME}"
info "results dir = ${RESULTS_DIR}/"
echo

# ---------------------------------------------------------------------------
# Main locust run
# ---------------------------------------------------------------------------
info "Running Locust (headless, auto-stops after ${RUN_TIME})..."
echo

locust \
    -f "$LOCUST_FILE" \
    --host "$HOST" \
    --users "$USERS" \
    --spawn-rate "$SPAWN_RATE" \
    --run-time "$RUN_TIME" \
    --headless \
    --csv="${RESULTS_DIR}/run_a" \
    --html="${RESULTS_DIR}/run_a_report.html" \
    --print-stats

# ---------------------------------------------------------------------------
# Post-run output
# ---------------------------------------------------------------------------
echo
echo "${C_GREEN}${C_BOLD}============================================================${C_RESET}"
echo "${C_GREEN}${C_BOLD}  RUN COMPLETE${C_RESET}"
echo "${C_GREEN}${C_BOLD}============================================================${C_RESET}"
echo

echo "${C_BOLD}Generated files:${C_RESET}"
for f in \
    "${RESULTS_DIR}/run_a_report.html" \
    "${RESULTS_DIR}/run_a_stats.csv" \
    "${RESULTS_DIR}/run_a_stats_history.csv" \
    "${RESULTS_DIR}/run_a_failures.csv"; do
    if [[ -f "$f" ]]; then
        echo "  ${C_GREEN}✓${C_RESET} $f"
    else
        echo "  ${C_YELLOW}?${C_RESET} $f  ${C_YELLOW}(not produced)${C_RESET}"
    fi
done
echo

echo "${C_BOLD}Next steps:${C_RESET}"
echo "  ${C_CYAN}1.${C_RESET} Open the HTML report in your browser:"
echo "       ${C_CYAN}open ${RESULTS_DIR}/run_a_report.html${C_RESET}"
echo
echo "  ${C_CYAN}2.${C_RESET} Check CloudWatch logs for the risk service:"
echo "       Log group: ${C_CYAN}/ecs/trading-risk-monitor${C_RESET}"
echo "       Filter:    ${C_CYAN}region-test-user-001${C_RESET}"
echo
echo "  ${C_CYAN}3.${C_RESET} In the log output, look for:"
echo "       • ${C_CYAN}daily_total=...${C_RESET} climbing toward 50000"
echo "       • A ${C_CYAN}risk: breach published${C_RESET} line once the limit is crossed"
echo "       • ${C_CYAN}primary_redis_latency=...${C_RESET} values for the baseline"
echo

echo "${C_BOLD}Screenshots to capture for the report:${C_RESET}"
echo "  ${C_YELLOW}□${C_RESET} HTML report — Response times chart"
echo "  ${C_YELLOW}□${C_RESET} HTML report — Statistics table (RPS, p50/p95, failures)"
echo "  ${C_YELLOW}□${C_RESET} CloudWatch — the breach-published log event"
echo "  ${C_YELLOW}□${C_RESET} CloudWatch — a few primary_redis_latency lines"
echo
