#!/usr/bin/env python3
"""
cascade_report.py — Post-experiment report for the Distributed Trading Risk Monitor.

Queries live AWS state and prints a formatted summary of:
  - ECS service health (all 8 services)
  - SQS queue depths (all queues + DLQs)
  - DynamoDB transaction count (last 30 min)
  - S3 audit log count (last 30 min)
  - Discrepancy analysis (submitted vs stored vs in-flight)

Usage:
    python scripts/cascade_report.py
    python scripts/cascade_report.py --window 60   # look back 60 minutes instead of 30
"""

import argparse
import sys
from datetime import datetime, timezone, timedelta

import boto3
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

REGION      = "us-west-2"
ACCOUNT     = "265898753907"
PROJECT     = "trading-risk-monitor"
CLUSTER     = f"{PROJECT}-cluster"
DYNAMO_TABLE = f"{PROJECT}-transactions"
S3_BUCKET   = f"{PROJECT}-audit-logs-{ACCOUNT}"
SQS_BASE    = f"https://sqs.{REGION}.amazonaws.com/{ACCOUNT}/{PROJECT}"

QUEUES = {
    "high-priority":     f"{SQS_BASE}-high-priority",
    "low-priority":      f"{SQS_BASE}-low-priority",
    "high-priority-dlq": f"{SQS_BASE}-high-priority-dlq",
    "low-priority-dlq":  f"{SQS_BASE}-low-priority-dlq",
    "alert":             f"{SQS_BASE}-alert",
    "alert-dlq":         f"{SQS_BASE}-alert-dlq",
}

SERVICES = [
    "transaction",
    "fraud",
    "risk",
    "compliance",
    "analytics",
    "audit-logging",
    "alert",
    "manual-review",
]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def section(title: str):
    width = 60
    print(f"\n{'=' * width}")
    print(f"  {title}")
    print(f"{'=' * width}")


def ts_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


def fmt_count(n: int) -> str:
    return f"{n:,}"


# ---------------------------------------------------------------------------
# ECS
# ---------------------------------------------------------------------------

def check_ecs(ecs) -> list[dict]:
    service_names = [f"{PROJECT}-{s}" for s in SERVICES]
    resp = ecs.describe_services(cluster=CLUSTER, services=service_names)
    results = []
    for svc in resp.get("services", []):
        results.append({
            "name":    svc["serviceName"].replace(f"{PROJECT}-", ""),
            "running": svc["runningCount"],
            "desired": svc["desiredCount"],
            "pending": svc["pendingCount"],
            "status":  svc["status"],
        })
    # preserve SERVICES order
    order = {s: i for i, s in enumerate(SERVICES)}
    results.sort(key=lambda r: order.get(r["name"], 99))
    return results


# ---------------------------------------------------------------------------
# SQS
# ---------------------------------------------------------------------------

def check_queues(sqs) -> dict[str, int]:
    depths = {}
    for name, url in QUEUES.items():
        try:
            resp = sqs.get_queue_attributes(
                QueueUrl=url,
                AttributeNames=["ApproximateNumberOfMessages",
                                 "ApproximateNumberOfMessagesNotVisible"],
            )
            attrs = resp.get("Attributes", {})
            visible   = int(attrs.get("ApproximateNumberOfMessages", 0))
            in_flight = int(attrs.get("ApproximateNumberOfMessagesNotVisible", 0))
            depths[name] = {"visible": visible, "in_flight": in_flight}
        except ClientError as e:
            depths[name] = {"visible": -1, "in_flight": -1, "error": str(e)}
    return depths


# ---------------------------------------------------------------------------
# DynamoDB
# ---------------------------------------------------------------------------

def count_dynamo(dynamo, since: datetime) -> tuple[int, int]:
    """Returns (total_items_in_window, flagged_as_fraud)."""
    since_iso = since.strftime("%Y-%m-%dT%H:%M:%S")
    total = 0
    flagged = 0
    kwargs = {
        "TableName": DYNAMO_TABLE,
        "FilterExpression": "#ts >= :since",
        "ExpressionAttributeNames": {"#ts": "timestamp"},
        "ExpressionAttributeValues": {":since": {"S": since_iso}},
        "Select": "ALL_ATTRIBUTES",
    }
    try:
        while True:
            resp = dynamo.scan(**kwargs)
            items = resp.get("Items", [])
            total += len(items)
            for item in items:
                if item.get("fraud_flag", {}).get("BOOL"):
                    flagged += 1
            last = resp.get("LastEvaluatedKey")
            if not last:
                break
            kwargs["ExclusiveStartKey"] = last
    except ClientError as e:
        print(f"  [WARN] DynamoDB scan failed: {e}", file=sys.stderr)
        return -1, -1
    return total, flagged


# ---------------------------------------------------------------------------
# S3
# ---------------------------------------------------------------------------

def count_s3(s3, since: datetime) -> int:
    """Count objects modified since `since`."""
    count = 0
    kwargs = {"Bucket": S3_BUCKET}
    try:
        while True:
            resp = s3.list_objects_v2(**kwargs)
            for obj in resp.get("Contents", []):
                if obj["LastModified"] >= since:
                    count += 1
            if resp.get("IsTruncated"):
                kwargs["ContinuationToken"] = resp["NextContinuationToken"]
            else:
                break
    except ClientError as e:
        print(f"  [WARN] S3 list failed: {e}", file=sys.stderr)
        return -1
    return count


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

def run_report(window_minutes: int):
    now   = datetime.now(timezone.utc)
    since = now - timedelta(minutes=window_minutes)

    ecs    = boto3.client("ecs",      region_name=REGION)
    sqs    = boto3.client("sqs",      region_name=REGION)
    dynamo = boto3.client("dynamodb", region_name=REGION)
    s3     = boto3.client("s3",       region_name=REGION)

    print(f"\n{'#' * 60}")
    print(f"  CASCADE EXPERIMENT — POST-RUN REPORT")
    print(f"  Generated : {ts_now()}")
    print(f"  Window    : last {window_minutes} minutes (since {since.strftime('%H:%M:%S UTC')})")
    print(f"{'#' * 60}")

    # ── ECS ──────────────────────────────────────────────────────────────────
    section("1. ECS SERVICE HEALTH")
    services = check_ecs(ecs)
    col = "{:<20} {:>9} {:>9} {:>9}  {}"
    print(col.format("SERVICE", "RUNNING", "DESIRED", "PENDING", "HEALTH"))
    print("-" * 58)
    unhealthy = []
    for s in services:
        ok = s["running"] == s["desired"] and s["pending"] == 0
        badge = "✓ OK" if ok else "✗ DEGRADED"
        if not ok:
            unhealthy.append(s["name"])
        print(col.format(
            s["name"],
            s["running"],
            s["desired"],
            s["pending"],
            badge,
        ))
    if unhealthy:
        print(f"\n  ⚠  Degraded services: {', '.join(unhealthy)}")
    else:
        print(f"\n  All {len(services)} services healthy.")

    # ── SQS ──────────────────────────────────────────────────────────────────
    section("2. SQS QUEUE DEPTHS")
    queue_data = check_queues(sqs)
    col = "{:<22} {:>10} {:>12}"
    print(col.format("QUEUE", "VISIBLE", "IN-FLIGHT"))
    print("-" * 46)
    total_unprocessed = 0
    total_dlq         = 0
    for name, d in queue_data.items():
        if "error" in d:
            print(col.format(name, "ERR", "ERR") + f"  ({d['error'][:40]})")
            continue
        v, f = d["visible"], d["in_flight"]
        print(col.format(name, fmt_count(v), fmt_count(f)))
        if "dlq" in name:
            total_dlq += v
        else:
            total_unprocessed += v + f

    print(f"\n  Total in-flight/unprocessed (non-DLQ): {fmt_count(total_unprocessed)}")
    if total_dlq > 0:
        print(f"  ⚠  Dead-letter messages: {fmt_count(total_dlq)}")
    else:
        print(f"  DLQs: empty (no dead-lettered messages)")

    # ── DynamoDB ─────────────────────────────────────────────────────────────
    section("3. DYNAMODB — TRANSACTIONS STORED")
    print(f"  Scanning '{DYNAMO_TABLE}' for records since {since.strftime('%H:%M:%S UTC')}...")
    dynamo_count, flagged_count = count_dynamo(dynamo, since)
    if dynamo_count >= 0:
        print(f"  Transactions stored : {fmt_count(dynamo_count)}")
        print(f"  Flagged as fraud    : {fmt_count(flagged_count)}")
        if dynamo_count > 0:
            fraud_pct = flagged_count / dynamo_count * 100
            print(f"  Fraud flag rate     : {fraud_pct:.1f}%")
    else:
        print("  [ERROR] Could not query DynamoDB.")

    # ── S3 ───────────────────────────────────────────────────────────────────
    section("4. S3 — AUDIT LOGS WRITTEN")
    print(f"  Listing '{S3_BUCKET}' for objects since {since.strftime('%H:%M:%S UTC')}...")
    s3_count = count_s3(s3, since)
    if s3_count >= 0:
        print(f"  Audit log objects   : {fmt_count(s3_count)}")
    else:
        print("  [ERROR] Could not list S3 bucket.")

    # ── Discrepancy Analysis ─────────────────────────────────────────────────
    section("5. DISCREPANCY ANALYSIS")
    if dynamo_count >= 0 and s3_count >= 0:
        total_in_queues = sum(
            d["visible"] + d["in_flight"]
            for d in queue_data.values()
            if "error" not in d
        )
        total_accounted = dynamo_count + total_in_queues

        print(f"  Transactions in DynamoDB       : {fmt_count(dynamo_count)}")
        print(f"  Messages still in queues       : {fmt_count(total_in_queues)}")
        print(f"  Audit logs in S3               : {fmt_count(s3_count)}")

        audit_gap = dynamo_count - s3_count
        if audit_gap > 0:
            print(f"\n  ⚠  {fmt_count(audit_gap)} transactions stored in DynamoDB but NOT yet in S3")
            print(f"     (audit-logging service may be lagging or was killed during experiment)")
        elif audit_gap < 0:
            print(f"\n  ⚠  S3 has {fmt_count(-audit_gap)} more objects than DynamoDB records")
            print(f"     (possible duplicate writes or pre-existing objects in window)")
        else:
            print(f"\n  ✓  DynamoDB and S3 counts match exactly.")

        if total_dlq > 0:
            print(f"\n  ⚠  {fmt_count(total_dlq)} messages in DLQs — these were NOT processed")
            print(f"     before their retry limit was reached (likely during the kill window)")
        else:
            print(f"  ✓  No dead-lettered messages — all transactions were eventually processed.")
    else:
        print("  Cannot compute discrepancies (one or more queries failed).")

    # ── Footer ───────────────────────────────────────────────────────────────
    print(f"\n{'#' * 60}")
    print(f"  Report complete — {ts_now()}")
    print(f"{'#' * 60}\n")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Cascade experiment post-run report")
    parser.add_argument(
        "--window", type=int, default=30,
        help="Look-back window in minutes (default: 30)",
    )
    args = parser.parse_args()
    run_report(args.window)
