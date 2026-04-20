#!/usr/bin/env python3
"""
reconcile.py — Data integrity audit after the audit Locust test.

Reads audit_submitted.csv, then cross-checks every submitted transaction
against DynamoDB, S3 audit logs, and SQS DLQs.

Usage:
    python3 scripts/reconcile.py [--csv locust/audit_submitted.csv]
"""

import argparse
import csv
import json
import sys
from datetime import datetime, timezone, timedelta

import boto3
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

REGION    = "us-west-2"
ACCOUNT   = "265898753907"
TABLE     = "trading-risk-monitor-transactions"
S3_BUCKET = "trading-risk-monitor-audit-logs-265898753907"
SQS_BASE  = f"https://sqs.{REGION}.amazonaws.com/{ACCOUNT}/trading-risk-monitor"

DLQS = [
    "fraud-dlq",
    "risk-dlq",
    "compliance-dlq",
    "analytics-dlq",
    "audit-logging-dlq",
]

DEFAULT_CSV = "locust/audit_submitted.csv"

# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------

GREEN  = "\033[32m"
RED    = "\033[31m"
YELLOW = "\033[33m"
BOLD   = "\033[1m"
RESET  = "\033[0m"

def _ok(label: str, value):
    print(f"  {GREEN}✓{RESET}  {label:<55} {BOLD}{value}{RESET}")

def _warn(label: str, value):
    print(f"  {YELLOW}!{RESET}  {label:<55} {BOLD}{YELLOW}{value}{RESET}")

def _fail(label: str, value):
    print(f"  {RED}✗{RESET}  {label:<55} {BOLD}{RED}{value}{RESET}")

def _section(title: str):
    print(f"\n{BOLD}{'─' * 65}{RESET}")
    print(f"{BOLD}  {title}{RESET}")
    print(f"{BOLD}{'─' * 65}{RESET}")

# ---------------------------------------------------------------------------
# Step 1 — Read CSV
# ---------------------------------------------------------------------------

def read_csv(path: str) -> list[dict]:
    """Return rows where http_status == '202'."""
    rows = []
    try:
        with open(path, newline="") as f:
            for row in csv.DictReader(f):
                if row.get("http_status", "").strip() == "202":
                    rows.append(row)
    except FileNotFoundError:
        print(f"{RED}ERROR:{RESET} CSV not found: {path}")
        sys.exit(1)
    return rows

# ---------------------------------------------------------------------------
# Step 2 — DynamoDB lookup
# ---------------------------------------------------------------------------

def check_dynamo(dynamo, rows: list[dict]) -> tuple[int, int, list[dict]]:
    """
    For each row query DynamoDB with get_item.
    Returns (found, missing, missing_rows).
    """
    found = 0
    missing = 0
    missing_rows: list[dict] = []

    total = len(rows)
    print(f"  Querying DynamoDB for {total:,} transactions …")

    for i, row in enumerate(rows, 1):
        tx_id = row["transaction_id"].strip()
        ts    = row["timestamp"].strip()
        if not tx_id or not ts:
            missing += 1
            missing_rows.append(row)
            continue

        try:
            resp = dynamo.get_item(
                TableName=TABLE,
                Key={
                    "transaction_id": {"S": tx_id},
                    "timestamp":      {"S": ts},
                },
            )
            if resp.get("Item"):
                found += 1
            else:
                missing += 1
                missing_rows.append(row)
        except ClientError as e:
            print(f"  {YELLOW}  DynamoDB error for {tx_id}: {e}{RESET}")
            missing += 1
            missing_rows.append(row)

        if i % 500 == 0:
            print(f"    … {i:,}/{total:,} checked (found={found} missing={missing})")

    return found, missing, missing_rows


def scan_duplicates(dynamo) -> dict[str, int]:
    """
    Scan DynamoDB for all items with user_id beginning 'audit-user-'.
    Return a dict of transaction_id → count; keep only those with count > 1.
    """
    print("  Scanning DynamoDB for audit-user-* duplicates (full scan) …")
    counts: dict[str, int] = {}
    kwargs = {
        "TableName": TABLE,
        "FilterExpression": "begins_with(user_id, :prefix)",
        "ExpressionAttributeValues": {":prefix": {"S": "audit-user-"}},
        "ProjectionExpression": "transaction_id",
    }
    pages = 0
    while True:
        resp = dynamo.scan(**kwargs)
        pages += 1
        for item in resp.get("Items", []):
            tx_id = item.get("transaction_id", {}).get("S", "")
            if tx_id:
                counts[tx_id] = counts.get(tx_id, 0) + 1
        if not resp.get("LastEvaluatedKey"):
            break
        kwargs["ExclusiveStartKey"] = resp["LastEvaluatedKey"]
        if pages % 10 == 0:
            print(f"    … scanned {pages} pages so far")

    return {k: v for k, v in counts.items() if v > 1}

# ---------------------------------------------------------------------------
# Step 3 — S3 audit log count
# ---------------------------------------------------------------------------

def count_s3_audit_entries(s3, minutes: int = 30) -> tuple[int, int]:
    """
    List all objects in S3_BUCKET modified in the last `minutes` minutes.
    Download each, count JSON entries (objects or array elements).
    Returns (object_count, entry_count).
    """
    since = datetime.now(timezone.utc) - timedelta(minutes=minutes)
    keys: list[str] = []

    kwargs: dict = {"Bucket": S3_BUCKET}
    try:
        while True:
            resp = s3.list_objects_v2(**kwargs)
            for obj in resp.get("Contents", []):
                lm = obj["LastModified"]
                if lm.tzinfo is None:
                    lm = lm.replace(tzinfo=timezone.utc)
                if lm >= since:
                    keys.append(obj["Key"])
            if resp.get("IsTruncated"):
                kwargs["ContinuationToken"] = resp["NextContinuationToken"]
            else:
                break
    except ClientError as e:
        print(f"  {YELLOW}S3 listing error: {e}{RESET}")
        return 0, 0

    entry_count = 0
    for key in keys:
        try:
            obj = s3.get_object(Bucket=S3_BUCKET, Key=key)
            raw = obj["Body"].read().decode("utf-8").strip()
            if not raw:
                continue
            parsed = json.loads(raw)
            if isinstance(parsed, list):
                entry_count += len(parsed)
            elif isinstance(parsed, dict):
                entry_count += 1
        except Exception as e:
            print(f"  {YELLOW}  Could not parse s3://{S3_BUCKET}/{key}: {e}{RESET}")

    return len(keys), entry_count

# ---------------------------------------------------------------------------
# Step 4 — DLQ depths
# ---------------------------------------------------------------------------

def check_dlqs(sqs) -> dict[str, int]:
    depths: dict[str, int] = {}
    for name in DLQS:
        url = f"{SQS_BASE}-{name}"
        try:
            resp = sqs.get_queue_attributes(
                QueueUrl=url,
                AttributeNames=["ApproximateNumberOfMessages"],
            )
            depths[name] = int(resp["Attributes"]["ApproximateNumberOfMessages"])
        except ClientError as e:
            depths[name] = -1
            print(f"  {YELLOW}  Could not read {name}: {e}{RESET}")
    return depths

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

def print_report(
    csv_path: str,
    submitted: int,
    found: int,
    missing: int,
    missing_rows: list[dict],
    s3_objects: int,
    s3_entries: int,
    dlq_depths: dict[str, int],
    duplicates: dict[str, int],
):
    _section("RECONCILIATION REPORT")
    print(f"  CSV source : {csv_path}")
    print(f"  Generated  : {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}")

    _section("1. Transactions Submitted (from CSV, status=202)")
    _ok("Submitted transactions", f"{submitted:,}")

    _section("2. DynamoDB Presence Check")
    _ok("Found in DynamoDB", f"{found:,}")
    fn = _ok if missing == 0 else _fail
    fn("Missing from DynamoDB", f"{missing:,}")
    if missing > 0 and len(missing_rows) <= 20:
        print(f"\n  {YELLOW}Missing transaction_ids:{RESET}")
        for r in missing_rows:
            print(f"    seq={r.get('sequence_number','?'):>5}  "
                  f"tx={r.get('transaction_id','?')}  "
                  f"user={r.get('user_id','?')}")
    elif missing > 20:
        print(f"  {YELLOW}(first 20 of {missing} missing):{RESET}")
        for r in missing_rows[:20]:
            print(f"    seq={r.get('sequence_number','?'):>5}  "
                  f"tx={r.get('transaction_id','?')}  "
                  f"user={r.get('user_id','?')}")

    _section("3. S3 Audit Log Entries (last 30 min)")
    _ok("S3 objects written", f"{s3_objects:,}")
    fn = _ok if s3_entries > 0 else _warn
    fn("Total audit entries (JSON records)", f"{s3_entries:,}")

    _section("4. DLQ Depths")
    total_dlq = 0
    for name, depth in dlq_depths.items():
        total_dlq += max(depth, 0)
        if depth < 0:
            _warn(name, "could not read")
        elif depth == 0:
            _ok(name, "0  (clean)")
        else:
            _fail(name, f"{depth}  ← messages stuck in DLQ")

    _section("5. Duplicate Detection (audit-user-* in DynamoDB)")
    if not duplicates:
        _ok("Duplicate transaction_ids", "none  ✓")
    else:
        _fail("Duplicate transaction_ids found", f"{len(duplicates):,}")
        for tx_id, count in list(duplicates.items())[:10]:
            print(f"    {tx_id}  appears {count}× in DynamoDB")
        if len(duplicates) > 10:
            print(f"    … and {len(duplicates) - 10} more")

    _section("6. Discrepancy Summary")
    dlq_total_display = total_dlq if total_dlq >= 0 else "?"
    print(f"""
  Submitted (CSV 202)        = {submitted:>8,}
  Found in DynamoDB          = {found:>8,}
  Missing from DynamoDB      = {missing:>8,}
  Total messages in DLQs     = {dlq_total_display!s:>8}
  S3 audit entries           = {s3_entries:>8,}
  Duplicate tx_ids           = {len(duplicates):>8,}

  Expected:  submitted == found + missing
  Actual  :  {submitted:,} == {found:,} + {missing:,}  →  {"✓ MATCH" if submitted == found + missing else f"✗ MISMATCH (delta={(found + missing) - submitted:+,})"}
""")

    if missing == 0 and total_dlq == 0 and not duplicates:
        print(f"  {GREEN}{BOLD}✓ All {submitted:,} transactions fully reconciled — no discrepancies.{RESET}\n")
    else:
        issues = []
        if missing:    issues.append(f"{missing} missing from DynamoDB")
        if total_dlq:  issues.append(f"{total_dlq} messages in DLQs")
        if duplicates: issues.append(f"{len(duplicates)} duplicate tx_ids")
        print(f"  {RED}{BOLD}✗ Issues found: {', '.join(issues)}{RESET}\n")

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Audit Locust test reconciliation")
    parser.add_argument("--csv", default=DEFAULT_CSV,
                        help=f"Path to audit_submitted.csv (default: {DEFAULT_CSV})")
    parser.add_argument("--s3-minutes", type=int, default=30,
                        help="S3 look-back window in minutes (default: 30)")
    parser.add_argument("--skip-scan", action="store_true",
                        help="Skip DynamoDB duplicate scan (slow on large tables)")
    args = parser.parse_args()

    dynamo = boto3.client("dynamodb", region_name=REGION)
    s3     = boto3.client("s3",       region_name=REGION)
    sqs    = boto3.client("sqs",      region_name=REGION)

    # ── Step 1: CSV ──────────────────────────────────────────────────────────
    _section("Step 1 — Reading CSV")
    rows = read_csv(args.csv)
    submitted = len(rows)
    print(f"  Loaded {submitted:,} rows with status=202 from {args.csv}")

    if submitted == 0:
        print(f"  {RED}No successful submissions found in CSV — nothing to reconcile.{RESET}")
        sys.exit(1)

    # ── Step 2: DynamoDB presence ────────────────────────────────────────────
    _section("Step 2 — DynamoDB Presence Check")
    found, missing, missing_rows = check_dynamo(dynamo, rows)

    # ── Step 3: S3 ───────────────────────────────────────────────────────────
    _section("Step 3 — S3 Audit Log Count")
    print(f"  Listing s3://{S3_BUCKET}  (last {args.s3_minutes} min) …")
    s3_objects, s3_entries = count_s3_audit_entries(s3, minutes=args.s3_minutes)
    print(f"  Found {s3_objects} objects → {s3_entries:,} audit entries")

    # ── Step 4: DLQs ─────────────────────────────────────────────────────────
    _section("Step 4 — DLQ Depths")
    dlq_depths = check_dlqs(sqs)
    for name, depth in dlq_depths.items():
        print(f"  {name:<30} depth={depth}")

    # ── Step 5: Duplicates ───────────────────────────────────────────────────
    duplicates: dict[str, int] = {}
    if not args.skip_scan:
        _section("Step 5 — Duplicate Detection")
        duplicates = scan_duplicates(dynamo)
        print(f"  Duplicate transaction_ids: {len(duplicates)}")
    else:
        print(f"\n  {YELLOW}NOTE{RESET}  Duplicate scan skipped (--skip-scan)")

    # ── Report ───────────────────────────────────────────────────────────────
    print_report(
        csv_path=args.csv,
        submitted=submitted,
        found=found,
        missing=missing,
        missing_rows=missing_rows,
        s3_objects=s3_objects,
        s3_entries=s3_entries,
        dlq_depths=dlq_depths,
        duplicates=duplicates,
    )


if __name__ == "__main__":
    main()
