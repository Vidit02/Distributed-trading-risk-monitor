#!/usr/bin/env bash
#
# experiment5_cap_test.sh — CAP theorem experiment runner.
#
# Runs three back-to-back load tests that demonstrate the CAP tradeoffs of the
# Risk Monitor service across region configurations:
#
#   Run A — Single Region                (baseline)
#   Run B — Dual Region, AP mode         (local-only writes, fast, inconsistent)
#   Run C — Dual Region, CP mode         (dual-write, slower, consistent)
#
# The script pauses before each run so you can reconfigure the ECS services'
# REDIS_SYNC_MODE env var and flush the Redis counters.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — override via env vars when invoking the script.
# ---------------------------------------------------------------------------
WEST_ALB_DNS="${WEST_ALB_DNS:-YOUR_WEST_ALB_DNS_HERE}"
EAST_ALB_DNS="${EAST_ALB_DNS:-}"   # empty → runs B and C are skipped

WEST_REDIS_ENDPOINT="${WEST_REDIS_ENDPOINT:-YOUR_WEST_REDIS_ENDPOINT_HERE}"
WEST_REDIS_PORT="${WEST_REDIS_PORT:-6379}"
EAST_REDIS_ENDPOINT="${EAST_REDIS_ENDPOINT:-YOUR_EAST_REDIS_ENDPOINT_HERE}"
EAST_REDIS_PORT="${EAST_REDIS_PORT:-6379}"

LOCUST_USERS="${LOCUST_USERS:-100}"
LOCUST_SPAWN_RATE="${LOCUST_SPAWN_RATE:-100}"
LOCUST_RUN_TIME="${LOCUST_RUN_TIME:-30s}"

TEST_USER="${TEST_USER:-region-test-user-001}"
REDIS_KEY="risk:user:${TEST_USER}:daily"

RESULTS_DIR="results"
LOCUST_FILE="locust/region_test.py"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_RESET=$'\e[0m'
    C_BOLD=$'\e[1m'
    C_RED=$'\e[31m'
    C_GREEN=$'\e[32m'
    C_YELLOW=$'\e[33m'
    C_BLUE=$'\e[34m'
    C_MAGENTA=$'\e[35m'
    C_CYAN=$'\e[36m'
else
    C_RESET="" C_BOLD="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_MAGENTA="" C_CYAN=""
fi

banner() {
    local color="$1"; shift
    echo
    echo "${color}${C_BOLD}============================================================${C_RESET}"
    echo "${color}${C_BOLD}  $*${C_RESET}"
    echo "${color}${C_BOLD}============================================================${C_RESET}"
}

info()  { echo "${C_CYAN}[info]${C_RESET}  $*"; }
warn()  { echo "${C_YELLOW}[warn]${C_RESET}  $*"; }
err()   { echo "${C_RED}[error]${C_RESET} $*" >&2; }
step()  { echo "${C_MAGENTA}→${C_RESET} $*"; }

pause() {
    local prompt="${1:-Press ENTER to continue...}"
    read -r -p "${C_YELLOW}${prompt}${C_RESET} "
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
banner "$C_BLUE" "PRE-FLIGHT CHECKS"

if [[ "$WEST_ALB_DNS" == "YOUR_WEST_ALB_DNS_HERE" ]]; then
    err "WEST_ALB_DNS is not set."
    err "Edit the script or export WEST_ALB_DNS=<your west ALB DNS> before running."
    exit 1
fi

if ! command -v locust >/dev/null 2>&1; then
    err "locust is not installed or not on PATH."
    err "Install with: pip install -r locust/requirements.txt"
    exit 1
fi

if [[ ! -f "$LOCUST_FILE" ]]; then
    err "Cannot find $LOCUST_FILE. Run this script from the project root."
    exit 1
fi

mkdir -p "$RESULTS_DIR"

info "west ALB     = ${C_GREEN}http://${WEST_ALB_DNS}${C_RESET}"
info "east ALB     = ${C_GREEN}${EAST_ALB_DNS:-<not set — runs B & C will be skipped>}${C_RESET}"
info "locust users = ${LOCUST_USERS}  spawn-rate = ${LOCUST_SPAWN_RATE}  run-time = ${LOCUST_RUN_TIME}"
info "results dir  = ${RESULTS_DIR}/"
echo

# ---------------------------------------------------------------------------
# RUN A — Single Region baseline
# ---------------------------------------------------------------------------
banner "$C_GREEN" "RUN A — SINGLE REGION (baseline)"

cat <<EOF
${C_BOLD}What this measures:${C_RESET}
  One region, one Redis. Single-writer, no cross-region traffic. This is the
  performance ceiling you can never beat — everything else adds latency.

${C_BOLD}Before starting, make sure on the ${C_YELLOW}WEST${C_RESET}${C_BOLD} ECS cluster:${C_RESET}
  • REDIS_SYNC_MODE     = ${C_CYAN}single${C_RESET}
  • REDIS_REGION_LABEL  = ${C_CYAN}us-west-2${C_RESET}
  (Update the risk task definition, force a new deployment, wait for steady state.)

${C_BOLD}Flush the Redis counter so you start from zero:${C_RESET}
  ${C_CYAN}redis-cli -h ${WEST_REDIS_ENDPOINT} -p ${WEST_REDIS_PORT} --tls DEL ${REDIS_KEY}${C_RESET}
EOF
echo
pause "Press ENTER when west is in 'single' mode and Redis is flushed..."

step "Running Locust (single region, ${LOCUST_RUN_TIME})..."
locust \
    -f "$LOCUST_FILE" \
    --host "http://${WEST_ALB_DNS}" \
    --users "$LOCUST_USERS" \
    --spawn-rate "$LOCUST_SPAWN_RATE" \
    --run-time "$LOCUST_RUN_TIME" \
    --headless \
    --csv="${RESULTS_DIR}/run_a" \
    --html="${RESULTS_DIR}/run_a_report.html"

step "Post-run checks for Run A:"
cat <<EOF
  1. Check the Redis counter (should be ≈ ${LOCUST_USERS} × 1000 × run_time/requests):
     ${C_CYAN}redis-cli -h ${WEST_REDIS_ENDPOINT} -p ${WEST_REDIS_PORT} --tls GET ${REDIS_KEY}${C_RESET}

  2. Screenshot:
     • ${RESULTS_DIR}/run_a_report.html — the Locust HTML report (latency, RPS, failures)
     • CloudWatch Logs — a few [us-west-2] risk: ... lines with primary_redis_latency
EOF
echo

# ---------------------------------------------------------------------------
# RUN B — Dual Region, AP mode
# ---------------------------------------------------------------------------
if [[ -z "$EAST_ALB_DNS" ]]; then
    warn "EAST_ALB_DNS not set — skipping RUN B (AP) and RUN C (CP)."
    echo
else
    banner "$C_YELLOW" "RUN B — DUAL REGION, AP MODE (local writes, inconsistent)"

    cat <<EOF
${C_BOLD}What this measures:${C_RESET}
  Two regions, two independent Redis clusters, each writing only locally.
  Low latency (no cross-region hop) but the counters DIVERGE — each region
  thinks the user has spent only ~\$50k, while combined they've spent \$100k.
  This is the AP corner: Availability + Partition tolerance, no Consistency.

${C_BOLD}Before starting:${C_RESET}
  On ${C_YELLOW}BOTH${C_RESET} ECS clusters (west and east), set:
  • REDIS_SYNC_MODE     = ${C_CYAN}local${C_RESET}
  • REDIS_REGION_LABEL  = ${C_CYAN}us-west-2${C_RESET} / ${C_CYAN}us-east-1${C_RESET} respectively
  (Force a new deployment on each, wait for steady state.)

${C_BOLD}Flush ${C_YELLOW}both${C_RESET}${C_BOLD} Redis clusters so you start from zero:${C_RESET}
  ${C_CYAN}redis-cli -h ${WEST_REDIS_ENDPOINT} -p ${WEST_REDIS_PORT} --tls DEL ${REDIS_KEY}${C_RESET}
  ${C_CYAN}redis-cli -h ${EAST_REDIS_ENDPOINT} -p ${EAST_REDIS_PORT} --tls DEL ${REDIS_KEY}${C_RESET}
EOF
    echo
    pause "Press ENTER when both regions are in 'local' mode and both Redis keys are flushed..."

    step "Running Locust (dual-region AP, ${LOCUST_RUN_TIME})..."
    locust \
        -f "$LOCUST_FILE" \
        --host "http://${WEST_ALB_DNS}" \
        --east-host "http://${EAST_ALB_DNS}" \
        --users "$LOCUST_USERS" \
        --spawn-rate "$LOCUST_SPAWN_RATE" \
        --run-time "$LOCUST_RUN_TIME" \
        --headless \
        --csv="${RESULTS_DIR}/run_b" \
        --html="${RESULTS_DIR}/run_b_report.html"

    step "Post-run checks for Run B (the ${C_RED}${C_BOLD}consistency violation${C_RESET}):"
    cat <<EOF
  1. Read both Redis counters — each should be ≈ \$50k (half the total):
     ${C_CYAN}redis-cli -h ${WEST_REDIS_ENDPOINT} -p ${WEST_REDIS_PORT} --tls GET ${REDIS_KEY}${C_RESET}
     ${C_CYAN}redis-cli -h ${EAST_REDIS_ENDPOINT} -p ${EAST_REDIS_PORT} --tls GET ${REDIS_KEY}${C_RESET}

  2. Combined total: add the two values — should be ≈ \$100k.
     The ${C_BOLD}\$50k daily limit was blown past${C_RESET} but neither region detected a breach
     because each only sees its own half. ${C_RED}This is the whole point of the AP tradeoff.${C_RESET}

  3. Screenshot:
     • Both redis-cli GET outputs side by side
     • ${RESULTS_DIR}/run_b_report.html — per-region latency (WEST and EAST breakdowns)
EOF
    echo

# ---------------------------------------------------------------------------
# RUN C — Dual Region, CP mode
# ---------------------------------------------------------------------------
    banner "$C_RED" "RUN C — DUAL REGION, CP MODE (dual-write, consistent, slower)"

    cat <<EOF
${C_BOLD}What this measures:${C_RESET}
  Two regions, but every write goes to BOTH Redis clusters synchronously
  before returning. Counters stay in lockstep (a breach in one is a breach
  in both) but every request pays cross-region network latency. This is the
  CP corner: Consistency + Partition tolerance, Availability suffers.

${C_BOLD}Before starting:${C_RESET}
  On ${C_YELLOW}BOTH${C_RESET} ECS clusters, set:
  • REDIS_SYNC_MODE        = ${C_CYAN}dual-write${C_RESET}
  • REDIS_SECONDARY_ADDR   = ${C_CYAN}<the OTHER region's Redis>:${WEST_REDIS_PORT}${C_RESET}
      west task → REDIS_SECONDARY_ADDR=${EAST_REDIS_ENDPOINT}:${EAST_REDIS_PORT}
      east task → REDIS_SECONDARY_ADDR=${WEST_REDIS_ENDPOINT}:${WEST_REDIS_PORT}
  • REDIS_REGION_LABEL     = us-west-2 / us-east-1 respectively

${C_BOLD}Flush ${C_YELLOW}both${C_RESET}${C_BOLD} Redis clusters again:${C_RESET}
  ${C_CYAN}redis-cli -h ${WEST_REDIS_ENDPOINT} -p ${WEST_REDIS_PORT} --tls DEL ${REDIS_KEY}${C_RESET}
  ${C_CYAN}redis-cli -h ${EAST_REDIS_ENDPOINT} -p ${EAST_REDIS_PORT} --tls DEL ${REDIS_KEY}${C_RESET}
EOF
    echo
    pause "Press ENTER when both regions are in 'dual-write' mode and both Redis keys are flushed..."

    step "Running Locust (dual-region CP, ${LOCUST_RUN_TIME})..."
    locust \
        -f "$LOCUST_FILE" \
        --host "http://${WEST_ALB_DNS}" \
        --east-host "http://${EAST_ALB_DNS}" \
        --users "$LOCUST_USERS" \
        --spawn-rate "$LOCUST_SPAWN_RATE" \
        --run-time "$LOCUST_RUN_TIME" \
        --headless \
        --csv="${RESULTS_DIR}/run_c" \
        --html="${RESULTS_DIR}/run_c_report.html"

    step "Post-run checks for Run C (${C_GREEN}${C_BOLD}consistency restored${C_RESET}):"
    cat <<EOF
  1. Read both Redis counters — they should be ${C_GREEN}equal${C_RESET} and total ≈ \$50k
     (NOT \$100k this time — dual-write means each increment lands in both):
     ${C_CYAN}redis-cli -h ${WEST_REDIS_ENDPOINT} -p ${WEST_REDIS_PORT} --tls GET ${REDIS_KEY}${C_RESET}
     ${C_CYAN}redis-cli -h ${EAST_REDIS_ENDPOINT} -p ${EAST_REDIS_PORT} --tls GET ${REDIS_KEY}${C_RESET}

  2. Look at the HTML report — p50/p95 latency should be ${C_RED}significantly higher${C_RESET}
     than Run A and Run B. That's the CAP tax for consistency.

  3. CloudWatch Logs — look for ${C_CYAN}secondary_redis_latency${C_RESET} lines. Each one
     shows the cross-region hop that every write is now paying.

  4. Screenshot:
     • Both redis-cli GET outputs (should match!)
     • ${RESULTS_DIR}/run_c_report.html — the latency curve (compare to Run B)
EOF
    echo
fi

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
banner "$C_BLUE" "EXPERIMENT COMPLETE — EXPECTED COMPARISON"

cat <<'EOF'
┌─────────────────────┬───────────────┬──────────────────┬──────────────────┐
│        Metric       │   Run A       │   Run B (AP)     │   Run C (CP)     │
│                     │ (single-region)│ (local writes)   │ (dual-write)     │
├─────────────────────┼───────────────┼──────────────────┼──────────────────┤
│ Regions used        │ 1 (west)      │ 2 (west + east)  │ 2 (west + east)  │
│ Redis writes per tx │ 1             │ 1 (local only)   │ 2 (primary+sec)  │
│ p50 latency         │ LOW           │ LOW (same-ish)   │ HIGH (+cross-rgn)│
│ p95 latency         │ LOW           │ LOW              │ HIGHER           │
│ Total RPS achieved  │ baseline      │ ~2× baseline     │ < Run B          │
│ West Redis total    │ ≈ full total  │ ≈ half total     │ ≈ full total     │
│ East Redis total    │ n/a           │ ≈ half total     │ ≈ full total     │
│ Counters match?     │ n/a (single)  │ NO (diverge)     │ YES (in lockstep)│
│ Breach detected?    │ YES           │ NO (each half)   │ YES              │
│ CAP corner          │ single-node   │ A + P            │ C + P            │
└─────────────────────┴───────────────┴──────────────────┴──────────────────┘

Results written to ./results/run_{a,b,c}*.{csv,html}

Screenshot the HTML reports + the redis-cli GET outputs and you have the
full story: one system, three configurations, the CAP tradeoffs made visible.
EOF
echo
