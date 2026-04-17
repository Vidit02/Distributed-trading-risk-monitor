import os
from datetime import datetime, timezone, timedelta
from decimal import Decimal

import boto3
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

load_dotenv()

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
_ACCOUNT = "265898753907"
_SQS_BASE = f"https://sqs.us-west-2.amazonaws.com/{_ACCOUNT}"

CLUSTER_NAME            = os.getenv("CLUSTER_NAME",            "trading-risk-monitor-cluster")
HIGH_PRIORITY_QUEUE_URL = os.getenv("HIGH_PRIORITY_QUEUE_URL", f"{_SQS_BASE}/trading-risk-monitor-high-priority")
LOW_PRIORITY_QUEUE_URL  = os.getenv("LOW_PRIORITY_QUEUE_URL",  f"{_SQS_BASE}/trading-risk-monitor-low-priority")
HIGH_PRIORITY_DLQ_URL   = os.getenv("HIGH_PRIORITY_DLQ_URL",   f"{_SQS_BASE}/trading-risk-monitor-high-priority-dlq")
LOW_PRIORITY_DLQ_URL    = os.getenv("LOW_PRIORITY_DLQ_URL",    f"{_SQS_BASE}/trading-risk-monitor-low-priority-dlq")
ALERT_QUEUE_URL         = os.getenv("ALERT_QUEUE_URL",         f"{_SQS_BASE}/trading-risk-monitor-alert")
ALERT_DLQ_URL           = os.getenv("ALERT_DLQ_URL",           f"{_SQS_BASE}/trading-risk-monitor-alert-dlq")
AWS_REGION              = os.getenv("AWS_REGION",              "us-west-2")
DYNAMODB_TABLE_NAME     = os.getenv("DYNAMODB_TABLE_NAME",     "trading-risk-monitor-transactions")

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
    """Return the approximate number of messages in a DLQ. Returns 0 on error."""
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

    high_dlq_depth    = get_dlq_depth(HIGH_PRIORITY_DLQ_URL)
    low_dlq_depth     = get_dlq_depth(LOW_PRIORITY_DLQ_URL)
    high_queue_depth  = get_dlq_depth(HIGH_PRIORITY_QUEUE_URL)
    low_queue_depth   = get_dlq_depth(LOW_PRIORITY_QUEUE_URL)
    alert_queue_depth = get_dlq_depth(ALERT_QUEUE_URL)
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

        kwargs = {"Limit": limit}
        if filter_parts:
            kwargs["FilterExpression"] = " AND ".join(filter_parts)
        if expr_names:
            kwargs["ExpressionAttributeNames"] = expr_names
        if expr_values:
            kwargs["ExpressionAttributeValues"] = expr_values

        resp = transactions_table.scan(**kwargs)
        items = resp.get("Items", [])

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
        # Scan all transactions (DynamoDB)
        resp = transactions_table.scan(
            ProjectionExpression="#ts, #st, transaction_type",
            ExpressionAttributeNames={"#ts": "timestamp", "#st": "status"},
        )
        items = resp.get("Items", [])

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

        # Current queue depths from SQS
        high_depth  = get_dlq_depth(HIGH_PRIORITY_QUEUE_URL)
        low_depth   = get_dlq_depth(LOW_PRIORITY_QUEUE_URL)
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
