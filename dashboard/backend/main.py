import csv
import io
import json
import os
import time
import uuid
from datetime import datetime, timezone, timedelta
from decimal import Decimal

import boto3
import openpyxl
import requests as http_requests
from dotenv import load_dotenv
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

load_dotenv()

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
_ACCOUNT = "265898753907"
_SQS_BASE = f"https://sqs.us-west-2.amazonaws.com/{_ACCOUNT}"

ALB_URL             = os.getenv("ALB_URL",             "http://localhost:8080")
CLUSTER_NAME        = os.getenv("CLUSTER_NAME",        "trading-risk-monitor-cluster")
AWS_REGION          = os.getenv("AWS_REGION",          "us-west-2")
DYNAMODB_TABLE_NAME = os.getenv("DYNAMODB_TABLE_NAME", "trading-risk-monitor-transactions")

# Per-service queues (SNS fan-out architecture)
_B = f"{_SQS_BASE}/trading-risk-monitor"
HIGH_QUEUE_URLS = [f"{_B}-fraud",     f"{_B}-risk",          f"{_B}-compliance"]
LOW_QUEUE_URLS  = [f"{_B}-analytics", f"{_B}-audit-logging"]
ALERT_QUEUE_URL = f"{_B}-alert"

HIGH_DLQ_URLS   = [f"{_B}-fraud-dlq",     f"{_B}-risk-dlq",          f"{_B}-compliance-dlq"]
LOW_DLQ_URLS    = [f"{_B}-analytics-dlq", f"{_B}-audit-logging-dlq"]
ALERT_DLQ_URL   = f"{_B}-alert-dlq"

# Keep these for backwards-compat references in helper functions
HIGH_PRIORITY_QUEUE_URL = HIGH_QUEUE_URLS[0]
LOW_PRIORITY_QUEUE_URL  = LOW_QUEUE_URLS[0]
HIGH_PRIORITY_DLQ_URL   = HIGH_DLQ_URLS[0]
LOW_PRIORITY_DLQ_URL    = LOW_DLQ_URLS[0]

# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------
app = FastAPI(title="Trading Risk Monitor – Chaos Dashboard")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# AWS clients
# ---------------------------------------------------------------------------
ecs = boto3.client("ecs", region_name=AWS_REGION)
sqs = boto3.client("sqs", region_name=AWS_REGION)
dynamo = boto3.resource("dynamodb", region_name=AWS_REGION)
transactions_table = dynamo.Table(DYNAMODB_TABLE_NAME)

# ---------------------------------------------------------------------------
# Service definitions
# ---------------------------------------------------------------------------
SERVICES = [
    {"name": "transaction",   "display": "Transaction",    "queue": None,                "ecs": "trading-risk-monitor-transaction"},
    {"name": "fraud",         "display": "Fraud detection","queue": "high-priority",     "ecs": "trading-risk-monitor-fraud"},
    {"name": "risk",          "display": "Risk monitor",   "queue": "high-priority",     "ecs": "trading-risk-monitor-risk"},
    {"name": "compliance",    "display": "Compliance",     "queue": "high-priority",     "ecs": "trading-risk-monitor-compliance"},
    {"name": "analytics",     "display": "Analytics",      "queue": "low-priority",      "ecs": "trading-risk-monitor-analytics"},
    {"name": "audit-logging", "display": "Audit logging",  "queue": "low-priority",      "ecs": "trading-risk-monitor-audit-logging"},
    {"name": "alert",         "display": "Alert",          "queue": "alert",             "ecs": "trading-risk-monitor-alert"},
    {"name": "manual-review", "display": "Manual review",  "queue": "high-priority-dlq", "ecs": "trading-risk-monitor-manual-review"},
]

# ---------------------------------------------------------------------------
# In-memory state
# ---------------------------------------------------------------------------
delays: dict[str, int] = {}        # service name → delay ms (0 = no delay)
events: list[dict] = []            # chaos event log, newest first, max 20
upload_sessions: dict[str, list[dict]] = {}   # session_id → parsed rows

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def add_event(message: str) -> None:
    """Prepend a timestamped event and trim the list to 20 entries."""
    global events
    now = datetime.now().strftime("%H:%M:%S")
    events = [{"time": now, "message": message}] + events
    events = events[:20]


def get_dlq_depth(url: str) -> int:
    """Return the approximate number of messages in a single queue. Returns 0 on error."""
    if not url:
        return 0
    try:
        resp = sqs.get_queue_attributes(
            QueueUrl=url,
            AttributeNames=["ApproximateNumberOfMessages"],
        )
        return int(resp["Attributes"].get("ApproximateNumberOfMessages", 0))
    except Exception:
        return 0

def get_queue_depth_sum(urls: list[str]) -> int:
    """Sum approximate message counts across multiple queues."""
    return sum(get_dlq_depth(u) for u in urls)


def _service_by_name(name: str) -> dict:
    for svc in SERVICES:
        if svc["name"] == name:
            return svc
    raise HTTPException(status_code=404, detail=f"Unknown service: {name}")


def _dlq_url_for_queue(queue_label: str | None) -> str:
    if queue_label == "high-priority":
        return HIGH_PRIORITY_DLQ_URL
    if queue_label == "low-priority":
        return LOW_PRIORITY_DLQ_URL
    if queue_label == "alert":
        return ALERT_DLQ_URL
    return ""

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/api/status")
def get_status():
    """Return live service health, DLQ depths, and the event log."""
    try:
        ecs_names = [svc["ecs"] for svc in SERVICES]
        resp = ecs.describe_services(cluster=CLUSTER_NAME, services=ecs_names)
        ecs_map: dict[str, dict] = {}
        for svc_detail in resp.get("services", []):
            ecs_map[svc_detail["serviceName"]] = {
                "running": svc_detail.get("runningCount", 0),
                "desired": svc_detail.get("desiredCount", 0),
                "pending": svc_detail.get("pendingCount", 0),
            }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    service_statuses = []
    for svc in SERVICES:
        counts  = ecs_map.get(svc["ecs"], {"running": 0, "desired": 0, "pending": 0})
        running = counts["running"]
        desired = counts["desired"]
        pending = counts["pending"]
        delay_ms = delays.get(svc["name"], 0)
        scaling_up   = desired > running
        scaling_down = desired < running
        service_statuses.append({
            "name":         svc["name"],
            "display":      svc["display"],
            "queue":        svc["queue"],
            "healthy":      running > 0,
            "running":      running,
            "desired":      desired,
            "pending":      pending,
            "scaling_up":   scaling_up,
            "scaling_down": scaling_down,
            "delayed":      delay_ms > 0,
            "delay_ms":     delay_ms,
        })

    high_queue_depth  = get_queue_depth_sum(HIGH_QUEUE_URLS)
    low_queue_depth   = get_queue_depth_sum(LOW_QUEUE_URLS)
    alert_queue_depth = get_dlq_depth(ALERT_QUEUE_URL)
    high_dlq_depth    = get_queue_depth_sum(HIGH_DLQ_URLS)
    low_dlq_depth     = get_queue_depth_sum(LOW_DLQ_URLS)
    alert_dlq_depth   = get_dlq_depth(ALERT_DLQ_URL)

    return {
        "services":          service_statuses,
        "high_dlq_depth":    high_dlq_depth,
        "low_dlq_depth":     low_dlq_depth,
        "high_queue_depth":  high_queue_depth,
        "low_queue_depth":   low_queue_depth,
        "alert_queue_depth": alert_queue_depth,
        "alert_dlq_depth":   alert_dlq_depth,
        "events":            events,
    }


@app.post("/api/chaos/kill/{name}")
def kill_service(name: str):
    """Scale a service down to 0 running tasks."""
    svc = _service_by_name(name)
    try:
        ecs.update_service(
            cluster=CLUSTER_NAME,
            service=svc["ecs"],
            desiredCount=0,
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    add_event(f"Killed {svc['display']} service")
    return {"ok": True}


@app.post("/api/chaos/restart/{name}")
def restart_service(name: str):
    """Scale a service back up to 1 running task and replay DLQ messages."""
    svc = _service_by_name(name)
    dlq_url = _dlq_url_for_queue(svc["queue"])
    dlq_depth = get_dlq_depth(dlq_url)
    try:
        ecs.update_service(
            cluster=CLUSTER_NAME,
            service=svc["ecs"],
            desiredCount=1,
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    add_event(f"Restarted {svc['display']} — replayed {dlq_depth} DLQ messages")
    return {"ok": True}


@app.post("/api/chaos/delay/{name}")
def toggle_delay(name: str):
    """Toggle a simulated 3-second processing delay on a service."""
    svc = _service_by_name(name)
    current = delays.get(svc["name"], 0)
    if current == 0:
        delays[svc["name"]] = 3000
        add_event(f"Injected 3s delay into {svc['display']}")
        delayed = True
    else:
        delays[svc["name"]] = 0
        add_event(f"Removed delay from {svc['display']}")
        delayed = False
    return {"ok": True, "delayed": delayed}


@app.get("/api/transactions")
def get_transactions(priority: str = None, type: str = None, limit: int = 100):
    """Return recent transactions from DynamoDB, newest first."""
    try:
        filter_parts = []
        expr_names = {}
        expr_values = {}

        if priority and priority != "all":
            filter_parts.append("#pri = :priority")
            expr_names["#pri"] = "priority"
            expr_values[":priority"] = priority

        if type and type != "all":
            filter_parts.append("transaction_type = :type")
            expr_values[":type"] = type

        kwargs = {}
        if filter_parts:
            kwargs["FilterExpression"] = " AND ".join(filter_parts)
        if expr_names:
            kwargs["ExpressionAttributeNames"] = expr_names
        if expr_values:
            kwargs["ExpressionAttributeValues"] = expr_values

        items = []
        while True:
            resp = transactions_table.scan(**kwargs)
            items.extend(resp.get("Items", []))
            last = resp.get("LastEvaluatedKey")
            if not last or len(items) >= limit:
                break
            kwargs["ExclusiveStartKey"] = last
        items = items[:limit]

        # Sort newest first by timestamp
        items.sort(key=lambda x: x.get("timestamp", ""), reverse=True)

        transactions = []
        for item in items:
            raw_status = item.get("status", "pending")
            if raw_status == "flagged":
                display_status = "Fraud alert"
            elif raw_status == "clean":
                display_status = "Clean"
            else:
                display_status = "Pending"

            transactions.append({
                "transaction_id": item.get("transaction_id", ""),
                "user_id":        item.get("user_id", ""),
                "transaction_type": item.get("transaction_type", ""),
                "amount":         float(item.get("amount", 0)),
                "currency":       item.get("currency", "USD"),
                "priority":       item.get("priority", "low"),
                "status":         display_status,
                "timestamp":      item.get("timestamp", ""),
            })

        return {"transactions": transactions, "count": len(transactions)}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.get("/api/metrics")
def get_metrics():
    """Return real observability metrics from DynamoDB and SQS."""
    try:
        # Paginate through the full table (DynamoDB returns max 1 MB per call)
        scan_kwargs = {
            "ProjectionExpression": "#ts, #st, transaction_type",
            "ExpressionAttributeNames": {"#ts": "timestamp", "#st": "status"},
        }
        items = []
        while True:
            resp = transactions_table.scan(**scan_kwargs)
            items.extend(resp.get("Items", []))
            last = resp.get("LastEvaluatedKey")
            if not last:
                break
            scan_kwargs["ExclusiveStartKey"] = last

        # Transactions/min — count items with timestamp in last 60s
        now = datetime.now(timezone.utc)
        cutoff = (now - timedelta(seconds=60)).isoformat()
        tx_per_min = sum(1 for item in items if item.get("timestamp", "") >= cutoff)

        # Transaction volume by type
        type_counts = {"purchase": 0, "withdrawal": 0, "transfer": 0, "deposit": 0}
        total = len(items)
        flagged = 0
        for item in items:
            t = item.get("transaction_type", "")
            if t in type_counts:
                type_counts[t] += 1
            if item.get("status") == "flagged":
                flagged += 1

        error_rate = round((flagged / total * 100), 2) if total > 0 else 0.0

        # Current queue depths from SQS — summed across per-service queues
        high_depth  = get_queue_depth_sum(HIGH_QUEUE_URLS)
        low_depth   = get_queue_depth_sum(LOW_QUEUE_URLS)
        alert_depth = get_dlq_depth(ALERT_QUEUE_URL)

        return {
            "tx_per_min":        tx_per_min,
            "error_rate":        error_rate,
            "total":             total,
            "flagged":           flagged,
            "type_counts":       type_counts,
            "high_queue_depth":  high_depth,
            "low_queue_depth":   low_depth,
            "alert_queue_depth": alert_depth,
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


# ---------------------------------------------------------------------------
# Batch upload helpers
# ---------------------------------------------------------------------------

_COL_ALIASES = {
    "userid": "user_id", "user": "user_id",
    "amount": "amount", "price": "amount", "value": "amount",
    "currency": "currency", "curr": "currency", "ccy": "currency",
    "merchantid": "merchant_id", "merchant": "merchant_id",
    "transactiontype": "transaction_type", "txtype": "transaction_type",
    "type": "transaction_type", "kind": "transaction_type",
    "priority": "priority",
}

def _norm(k: str) -> str:
    return k.lower().replace(" ", "").replace("_", "").replace("-", "")

def _map_row(raw: dict) -> dict:
    return {_COL_ALIASES[_norm(k)]: str(v) for k, v in raw.items() if _COL_ALIASES.get(_norm(k))}

def _parse_excel(data: bytes) -> list[dict]:
    wb = openpyxl.load_workbook(io.BytesIO(data), read_only=True, data_only=True)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    if not rows:
        return []
    headers = [str(c).strip() if c is not None else "" for c in rows[0]]
    result = []
    for row in rows[1:]:
        raw = {headers[i]: (row[i] if row[i] is not None else "") for i in range(len(headers))}
        mapped = _map_row(raw)
        if mapped.get("user_id") and mapped.get("amount"):
            result.append(mapped)
    return result

def _parse_csv_file(data: bytes) -> list[dict]:
    text = data.decode("utf-8-sig")
    reader = csv.DictReader(io.StringIO(text))
    result = []
    for raw in reader:
        mapped = _map_row(raw)
        if mapped.get("user_id") and mapped.get("amount"):
            result.append(mapped)
    return result

def _derive_priority(amount: float) -> str:
    if amount >= 50000: return "critical"
    if amount >= 10000: return "high"
    if amount >= 1000:  return "medium"
    return "low"


# ---------------------------------------------------------------------------
# POST /api/upload — parse file, store session, return preview
# ---------------------------------------------------------------------------

@app.post("/api/upload")
async def upload_file(file: UploadFile = File(...)):
    data = await file.read()
    filename = (file.filename or "").lower()

    try:
        if filename.endswith(".csv"):
            rows = _parse_csv_file(data)
        elif filename.endswith((".xlsx", ".xls")):
            rows = _parse_excel(data)
        else:
            raise HTTPException(status_code=400, detail="Only .xlsx, .xls, or .csv files are accepted")
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Failed to parse file: {exc}")

    if not rows:
        raise HTTPException(status_code=400, detail="No valid rows found. Required columns: user_id, amount, currency, merchant_id, transaction_type")

    session_id = str(uuid.uuid4())
    upload_sessions[session_id] = rows

    preview = []
    for r in rows[:10]:
        amt = float(r.get("amount", 0) or 0)
        preview.append({
            "user_id":          r.get("user_id", ""),
            "amount":           amt,
            "currency":         r.get("currency", "USD"),
            "merchant_id":      r.get("merchant_id", ""),
            "transaction_type": r.get("transaction_type", "purchase"),
            "priority":         r.get("priority") or _derive_priority(amt),
        })

    return {"session_id": session_id, "count": len(rows), "preview": preview}


# ---------------------------------------------------------------------------
# GET /api/batch-submit/{session_id} — SSE stream that submits all rows
# ---------------------------------------------------------------------------

@app.get("/api/batch-submit/{session_id}")
def batch_submit(session_id: str):
    rows = upload_sessions.get(session_id)
    if rows is None:
        raise HTTPException(status_code=404, detail="Session not found. Re-upload the file.")

    total = len(rows)

    def send_one(row: dict) -> dict:
        amt = float(row.get("amount", 0) or 0)
        payload = {
            "user_id":          row.get("user_id", ""),
            "amount":           amt,
            "currency":         (row.get("currency") or "USD").upper(),
            "merchant_id":      row.get("merchant_id", "unknown"),
            "transaction_type": (row.get("transaction_type") or "purchase").lower(),
        }
        pri = row.get("priority")
        if pri:
            payload["priority"] = pri.lower()
        try:
            resp = http_requests.post(
                f"{ALB_URL}/transaction",
                json=payload,
                timeout=10,
            )
            if resp.status_code == 202:
                body = resp.json()
                return {"ok": True, "transaction_id": body.get("transaction_id", ""), "status": 202}
            return {"ok": False, "transaction_id": "", "status": resp.status_code, "error": resp.text[:120]}
        except Exception as exc:
            return {"ok": False, "transaction_id": "", "status": 0, "error": str(exc)[:120]}

    def generate():
        success = 0
        failed = 0
        start = time.time()

        yield f"data: {json.dumps({'type': 'start', 'total': total})}\n\n"

        for i, row in enumerate(rows):
            result = send_one(row)
            if result["ok"]:
                success += 1
            else:
                failed += 1

            elapsed = time.time() - start
            tps = (i + 1) / elapsed if elapsed > 0 else 0

            event = {
                "type":           "progress",
                "index":          i,
                "total":          total,
                "success":        success,
                "failed":         failed,
                "tps":            round(tps, 1),
                "transaction_id": result.get("transaction_id", ""),
                "ok":             result["ok"],
                "status":         result.get("status", 0),
                "user_id":        row.get("user_id", ""),
                "amount":         float(row.get("amount", 0) or 0),
                "error":          result.get("error", ""),
            }
            yield f"data: {json.dumps(event)}\n\n"

        elapsed = time.time() - start
        yield f"data: {json.dumps({'type': 'done', 'total': total, 'success': success, 'failed': failed, 'elapsed': round(elapsed, 1)})}\n\n"
        upload_sessions.pop(session_id, None)

    return StreamingResponse(generate(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})
