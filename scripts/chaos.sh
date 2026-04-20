#!/usr/bin/env bash
set -euo pipefail

CLUSTER="trading-risk-monitor-cluster"
REGION="us-west-2"
PROJECT="trading-risk-monitor"
SQS_BASE="https://sqs.${REGION}.amazonaws.com/265898753907/${PROJECT}"

HIGH_PRIORITY_URL="${SQS_BASE}-high-priority"
HIGH_PRIORITY_DLQ_URL="${SQS_BASE}-high-priority-dlq"
LOW_PRIORITY_URL="${SQS_BASE}-low-priority"
LOW_PRIORITY_DLQ_URL="${SQS_BASE}-low-priority-dlq"
ALERT_URL="${SQS_BASE}-alert"
ALERT_DLQ_URL="${SQS_BASE}-alert-dlq"

HIGH_PRIORITY_SERVICES=("fraud" "risk" "compliance")
ALL_SERVICES=("transaction" "fraud" "risk" "compliance" "analytics" "audit-logging" "alert" "manual-review")

ts() { date '+%H:%M:%S'; }

queue_depth() {
  local url="$1"
  local name="$2"
  local depth
  depth=$(aws sqs get-queue-attributes \
    --region "$REGION" \
    --queue-url "$url" \
    --attribute-names ApproximateNumberOfMessages \
    --query 'Attributes.ApproximateNumberOfMessages' \
    --output text 2>/dev/null || echo "ERR")
  printf "  %-28s %s\n" "$name" "$depth"
}

print_queues() {
  echo "[$(ts)] Queue depths:"
  queue_depth "$HIGH_PRIORITY_URL"     "high-priority"
  queue_depth "$HIGH_PRIORITY_DLQ_URL" "high-priority-dlq"
  queue_depth "$LOW_PRIORITY_URL"      "low-priority"
  queue_depth "$LOW_PRIORITY_DLQ_URL"  "low-priority-dlq"
  queue_depth "$ALERT_URL"             "alert"
  queue_depth "$ALERT_DLQ_URL"         "alert-dlq"
}

cmd="${1:-}"

case "$cmd" in

# ---------------------------------------------------------------------------
kill)
  echo ""
  echo "=== [$(ts)] CHAOS: Killing fraud, risk, compliance ==="
  echo ""

  for svc in "${HIGH_PRIORITY_SERVICES[@]}"; do
    resource="service/${CLUSTER}/${PROJECT}-${svc}"
    echo "[$(ts)] Deregistering autoscaling for ${svc}..."
    aws application-autoscaling deregister-scalable-target \
      --region "$REGION" \
      --service-namespace ecs \
      --scalable-dimension ecs:service:DesiredCount \
      --resource-id "$resource" 2>/dev/null \
      && echo "[$(ts)] ✓ Autoscaling deregistered for ${svc}" \
      || echo "[$(ts)] ⚠ No autoscaling target found for ${svc} (already deregistered?)"
  done

  echo ""
  for svc in "${HIGH_PRIORITY_SERVICES[@]}"; do
    echo "[$(ts)] Setting desired count to 0 for ${svc}..."
    aws ecs update-service \
      --region "$REGION" \
      --cluster "$CLUSTER" \
      --service "${PROJECT}-${svc}" \
      --desired-count 0 \
      --query 'service.{name:serviceName,desired:desiredCount}' \
      --output table
    echo "[$(ts)] ✓ ${svc} desired count → 0"
  done

  echo ""
  echo "=== [$(ts)] All high-priority services killed. Watching queues (Ctrl+C to stop) ==="
  echo ""

  while true; do
    print_queues
    echo ""
    sleep 30
  done
  ;;

# ---------------------------------------------------------------------------
restore)
  echo ""
  echo "=== [$(ts)] RESTORE: Bringing fraud, risk, compliance back to 1 ==="
  echo ""

  for svc in "${HIGH_PRIORITY_SERVICES[@]}"; do
    echo "[$(ts)] Setting desired count to 1 for ${svc}..."
    aws ecs update-service \
      --region "$REGION" \
      --cluster "$CLUSTER" \
      --service "${PROJECT}-${svc}" \
      --desired-count 1 \
      --query 'service.{name:serviceName,desired:desiredCount}' \
      --output table
    echo "[$(ts)] ✓ ${svc} desired count → 1"
  done

  echo ""
  echo "[$(ts)] Run 'terraform apply' to re-register autoscaling targets."
  echo ""
  ;;

# ---------------------------------------------------------------------------
status)
  echo ""
  echo "=== [$(ts)] ECS Service Status ==="
  svc_args=()
  for svc in "${ALL_SERVICES[@]}"; do
    svc_args+=("${PROJECT}-${svc}")
  done
  aws ecs describe-services \
    --region "$REGION" \
    --cluster "$CLUSTER" \
    --services "${svc_args[@]}" \
    --query 'services[*].{Service:serviceName,Running:runningCount,Desired:desiredCount,Pending:pendingCount,Status:status}' \
    --output table

  echo ""
  echo "=== [$(ts)] Queue Depths ==="
  print_queues
  echo ""
  ;;

# ---------------------------------------------------------------------------
*)
  echo "Usage: $0 {kill|restore|status}"
  echo ""
  echo "  kill     — deregister autoscaling + set fraud/risk/compliance to 0, then watch queues"
  echo "  restore  — set fraud/risk/compliance back to 1"
  echo "  status   — show running/desired for all 8 services + all queue depths"
  exit 1
  ;;

esac
