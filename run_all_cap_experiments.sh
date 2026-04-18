#!/usr/bin/env bash
#
# run_all_cap_experiments.sh — run all three CAP theorem experiments
# (Run A, B, C) back-to-back against the same single ALB, switching the
# risk service's REDIS_SYNC_MODE between runs to simulate each CAP corner.
#
#   Run A — Single Region Baseline           REDIS_SYNC_MODE=single
#   Run B — AP Mode (local, inconsistent)    REDIS_SYNC_MODE=local
#   Run C — CP Mode (dual-write, consistent) REDIS_SYNC_MODE=dual-write

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
ALB_DNS="trading-risk-monitor-alb-703965592.us-west-2.elb.amazonaws.com"
HOST="http://${ALB_DNS}"
LOCUST_FILE="locust/region_test.py"
USERS=100
SPAWN_RATE=100
RUN_TIME="30s"
RESULTS_DIR="results"
CLUSTER="trading-risk-monitor-cluster"
SERVICE="trading-risk-monitor-risk"
REGION="us-west-2"
TASK_FAMILY="trading-risk-monitor-risk"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_RESET=$'\e[0m'
    C_BOLD=$'\e[1m'
    C_RED=$'\e[31m'
    C_GREEN=$'\e[32m'
    C_YELLOW=$'\e[33m'
    C_CYAN=$'\e[36m'
    C_MAGENTA=$'\e[35m'
else
    C_RESET="" C_BOLD="" C_RED="" C_GREEN="" C_YELLOW="" C_CYAN="" C_MAGENTA=""
fi

info()    { echo "${C_CYAN}[info]${C_RESET}  $*"; }
success() { echo "${C_GREEN}[ok]${C_RESET}    $*"; }
warn()    { echo "${C_YELLOW}[warn]${C_RESET}  $*"; }
err()     { echo "${C_RED}[error]${C_RESET} $*" >&2; }
step()    { echo "${C_MAGENTA}→${C_RESET} $*"; }

banner() {
    local color="$1"; shift
    echo
    echo "${color}${C_BOLD}============================================================${C_RESET}"
    echo "${color}${C_BOLD}  $*${C_RESET}"
    echo "${color}${C_BOLD}============================================================${C_RESET}"
}

# ---------------------------------------------------------------------------
# update_risk_sync_mode <sync_mode> <region_label>
#
# Re-registers the risk task definition with updated REDIS_SYNC_MODE and
# REDIS_REGION_LABEL env vars, forces a new deployment, and waits for the
# new task to come up.
# ---------------------------------------------------------------------------
update_risk_sync_mode() {
    local sync_mode="$1"
    local region_label="$2"

    step "Switching risk service → REDIS_SYNC_MODE=${C_CYAN}${sync_mode}${C_RESET} REDIS_REGION_LABEL=${C_CYAN}${region_label}${C_RESET}"

    local task_def
    task_def=$(aws ecs describe-task-definition \
        --task-definition "$TASK_FAMILY" \
        --region "$REGION" \
        --query 'taskDefinition' \
        --output json)

    # Patch env vars and strip fields that register-task-definition rejects.
    local new_input
    new_input=$(echo "$task_def" | jq --arg mode "$sync_mode" --arg label "$region_label" '
      .containerDefinitions[0].environment |= map(
        if .name == "REDIS_SYNC_MODE" then .value = $mode
        elif .name == "REDIS_REGION_LABEL" then .value = $label
        else . end
      ) | {
        family, containerDefinitions, cpu, memory, networkMode,
        requiresCompatibilities, executionRoleArn, taskRoleArn
      }')

    local new_arn
    new_arn=$(aws ecs register-task-definition \
        --cli-input-json "$new_input" \
        --region "$REGION" \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)

    info "Registered new task definition: $(basename "$new_arn")"

    aws ecs update-service \
        --cluster "$CLUSTER" \
        --service "$SERVICE" \
        --task-definition "$new_arn" \
        --force-new-deployment \
        --region "$REGION" \
        --query 'service.deployments[0].{status:status}' \
        --output text >/dev/null

    info "Forced new deployment on $SERVICE. Waiting 60s for the new task..."
    for i in {60..1}; do
        printf "\r   starting new task in... %2ds " "$i"
        sleep 1
    done
    printf "\r   new task should be up                       \n"
    info "Check CloudWatch log group /ecs/trading-risk-monitor (stream prefix 'risk') to verify the startup banner shows sync_mode=${sync_mode}."
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
banner "$C_CYAN" "PRE-FLIGHT CHECKS"

mkdir -p "$RESULTS_DIR"

for cmd in locust aws jq curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        err "$cmd is required but not on PATH."
        case "$cmd" in
            locust) echo "    pip install -r locust/requirements.txt" ;;
            aws)    echo "    brew install awscli   # or install from AWS docs" ;;
            jq)     echo "    brew install jq" ;;
        esac
        exit 1
    fi
done
success "locust, aws, jq, curl all present"

info "Testing ALB at ${C_CYAN}${HOST}/transaction${C_RESET}..."
healthcheck='{"user_id":"healthcheck","amount":1,"currency":"USD","transaction_type":"purchase"}'
set +e
hc_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
    -X POST "${HOST}/transaction" \
    -H "Content-Type: application/json" -d "$healthcheck")
curl_exit=$?
set -e
if [[ $curl_exit -ne 0 ]]; then
    err "Could not reach ALB at ${HOST} (curl exit ${curl_exit})."
    exit 1
fi
if [[ "$hc_status" != "202" ]]; then
    warn "ALB responded with HTTP ${hc_status} (expected 202). Continuing anyway."
else
    success "ALB healthy (HTTP 202)"
fi

info "locust: ${USERS} users, ${SPAWN_RATE}/s spawn, ${RUN_TIME} per run"
info "results dir: ${RESULTS_DIR}/"

# ---------------------------------------------------------------------------
# Run A — Single Region Baseline
# ---------------------------------------------------------------------------
banner "$C_GREEN" "RUN A: Single Region Baseline (REDIS_SYNC_MODE=single)"
info "Primary Redis only. This is the performance ceiling — no cross-region cost."

update_risk_sync_mode "single" "us-west-2"

step "Launching Locust (run A)..."
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

success "Run A complete. Check ${RESULTS_DIR}/run_a_report.html"
info "Sleeping 20s for SQS to drain before next run..."
sleep 20

# ---------------------------------------------------------------------------
# Run B — AP Mode
# ---------------------------------------------------------------------------
banner "$C_YELLOW" "RUN B: AP Mode — Available but Inconsistent (REDIS_SYNC_MODE=local)"
cat <<EOF
${C_BOLD}Why 'local' simulates AP:${C_RESET}
  In a real two-region setup, each region would have its own Redis cluster and
  each risk service instance would write only to its local Redis. Transactions
  processed independently in each region would each see only half the spend and
  neither would notice the combined limit was violated.
  Here we switch the single risk service to 'local' mode to demonstrate that
  behaviour from the service's point of view — it writes only to its local
  Redis and never cross-replicates.
EOF

update_risk_sync_mode "local" "us-west-2"

step "Launching Locust (run B)..."
locust \
    -f "$LOCUST_FILE" \
    --host "$HOST" \
    --users "$USERS" \
    --spawn-rate "$SPAWN_RATE" \
    --run-time "$RUN_TIME" \
    --headless \
    --csv="${RESULTS_DIR}/run_b" \
    --html="${RESULTS_DIR}/run_b_report.html" \
    --print-stats

success "Run B complete."
warn "In a real AP setup, two independent regions would each allow \$50K → \$100K total exposure (2x violation)."
info "Sleeping 20s for SQS to drain before next run..."
sleep 20

# ---------------------------------------------------------------------------
# Run C — CP Mode
# ---------------------------------------------------------------------------
banner "$C_RED" "RUN C: CP Mode — Consistent but Slow (REDIS_SYNC_MODE=dual-write)"
cat <<EOF
${C_BOLD}Why 'dual-write' is CP:${C_RESET}
  Every write goes to the primary (west) Redis AND synchronously to the
  secondary (east) Redis before the handler returns. The counters stay
  in lockstep but every request pays a cross-region network hop.

${C_YELLOW}WARNING:${C_RESET} the east Redis lives in an isolated us-east-1 VPC (no
peering). The west-region risk task cannot actually reach it, so dual-write
writes will fail and the service will log errors. The theoretical latency
penalty if it COULD reach the east Redis is ~60-100ms per write.
EOF

update_risk_sync_mode "dual-write" "us-west-2"

step "Launching Locust (run C)..."
locust \
    -f "$LOCUST_FILE" \
    --host "$HOST" \
    --users "$USERS" \
    --spawn-rate "$SPAWN_RATE" \
    --run-time "$RUN_TIME" \
    --headless \
    --csv="${RESULTS_DIR}/run_c" \
    --html="${RESULTS_DIR}/run_c_report.html" \
    --print-stats

success "Run C complete (or check if the risk service errored on east Redis unreachable)."
info "Sleeping 20s for SQS to drain..."
sleep 20

# ---------------------------------------------------------------------------
# Restore to single mode
# ---------------------------------------------------------------------------
banner "$C_CYAN" "CLEANUP"
update_risk_sync_mode "single" "us-west-2"
success "Restored risk service to single mode."

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
banner "$C_GREEN" "CAP THEOREM EXPERIMENT — RESULTS SUMMARY"

cat <<'EOF'

Generated reports:
  results/run_a_report.html  — Single region baseline
  results/run_b_report.html  — AP mode (local Redis only)
  results/run_c_report.html  — CP mode (dual-write)

Expected comparison:
┌──────────────────────┬───────────────┬───────────────┬───────────────┐
│ Metric               │ Run A (Single)│ Run B (AP)    │ Run C (CP)    │
├──────────────────────┼───────────────┼───────────────┼───────────────┤
│ Limit enforced?      │ Yes           │ No (2x in     │ Yes           │
│                      │               │ real 2-region)│               │
│ Avg latency          │ ~1000ms       │ ~1000ms       │ ~1060-1100ms  │
│ Transactions allowed │ 5 of 2600     │ ~5 per region │ 5 of 2600     │
│ If network breaks?   │ N/A           │ Both work     │ System halts  │
└──────────────────────┴───────────────┴───────────────┴───────────────┘

Screenshots to take:
  □ Run A HTML report — response times chart + statistics table
  □ Run B HTML report — response times chart + statistics table
  □ Run C HTML report — response times chart + statistics table
  □ CloudWatch: risk service logs showing daily_total and breach events
  □ CloudWatch: risk service logs showing primary_redis_latency
  □ CloudWatch: risk service startup log showing sync_mode for each run
  □ Terraform output showing two Redis endpoints (west + east)
  □ AWS Console: ElastiCache showing clusters in both us-west-2 and us-east-1

EOF
