#!/usr/bin/env bash
# build-push.sh — build Docker images, push to ECR, redeploy ECS services
# Run from the repo root after terraform apply.

set -euo pipefail

REGION="us-west-2"
CLUSTER="trading-risk-monitor-cluster"
SERVICES=("transaction" "fraud" "risk" "analytics" "audit-logging")

echo "==> Fetching AWS account ID"
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
ECR_BASE="$AWS_ACCOUNT.dkr.ecr.$REGION.amazonaws.com"

echo "==> Logging in to ECR"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ECR_BASE"

for svc in "${SERVICES[@]}"; do
  REPO="$ECR_BASE/trading-risk-monitor-$svc"

  echo ""
  echo "==> [$svc] Building image"
  docker build \
    --platform linux/amd64 \
    -t "trading-risk-monitor-$svc" \
    -f "services/$svc/Dockerfile" \
    .

  echo "==> [$svc] Tagging and pushing"
  docker tag "trading-risk-monitor-$svc" "$REPO:latest"
  docker push "$REPO:latest"
done

echo ""
echo "==> Forcing ECS redeployment for all services"
for svc in "${SERVICES[@]}"; do
  aws ecs update-service \
    --cluster "$CLUSTER" \
    --service "trading-risk-monitor-$svc" \
    --force-new-deployment \
    --region "$REGION" \
    --output json | jq -r '.service.serviceName + " → " + .service.status'
done

echo ""
echo "==> Done. Tasks are deploying. Check progress with:"
echo "    aws ecs list-tasks --cluster $CLUSTER --region $REGION"
