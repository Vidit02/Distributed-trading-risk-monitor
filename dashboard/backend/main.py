import os
from datetime import datetime

import boto3
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

load_dotenv()

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
CLUSTER_NAME = os.getenv("CLUSTER_NAME", "trading-risk-monitor-cluster")
HIGH_PRIORITY_QUEUE_URL = os.getenv("HIGH_PRIORITY_QUEUE_URL", "https://sqs.us-west-2.amazonaws.com/265898753907/trading-risk-monitor-high-priority")
LOW_PRIORITY_QUEUE_URL = os.getenv("LOW_PRIORITY_QUEUE_URL", "https://sqs.us-west-2.amazonaws.com/265898753907/trading-risk-monitor-low-priority")
HIGH_PRIORITY_DLQ_URL = os.getenv("HIGH_PRIORITY_DLQ_URL", "")
LOW_PRIORITY_DLQ_URL = os.getenv("LOW_PRIORITY_DLQ_URL", "")
AWS_REGION = os.getenv("AWS_REGION", "us-west-2")

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

# ---------------------------------------------------------------------------
# Service definitions
# ---------------------------------------------------------------------------
SERVICES = [
    {"name": "transaction",   "display": "Transaction",     "queue": None,            "ecs": "trading-risk-monitor-transaction"},
    {"name": "fraud",         "display": "Fraud detection", "queue": "high-priority", "ecs": "trading-risk-monitor-fraud"},
    {"name": "risk",          "display": "Risk monitor",    "queue": "high-priority", "ecs": "trading-risk-monitor-risk"},
    {"name": "analytics",     "display": "Analytics",       "queue": "low-priority",  "ecs": "trading-risk-monitor-analytics"},
    {"name": "audit-logging", "display": "Audit logging",   "queue": "low-priority",  "ecs": "trading-risk-monitor-audit-logging"},
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
        running_map: dict[str, int] = {}
        for svc_detail in resp.get("services", []):
            running_map[svc_detail["serviceName"]] = svc_detail.get("runningCount", 0)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    service_statuses = []
    for svc in SERVICES:
        running = running_map.get(svc["ecs"], 0)
        delay_ms = delays.get(svc["name"], 0)
        service_statuses.append({
            "name": svc["name"],
            "display": svc["display"],
            "queue": svc["queue"],
            "healthy": running > 0,
            "running": running,
            "delayed": delay_ms > 0,
            "delay_ms": delay_ms,
        })

    high_depth = get_dlq_depth(HIGH_PRIORITY_DLQ_URL)
    low_depth = get_dlq_depth(LOW_PRIORITY_DLQ_URL)
    high_queue_depth = get_dlq_depth(HIGH_PRIORITY_QUEUE_URL)
    low_queue_depth = get_dlq_depth(LOW_PRIORITY_QUEUE_URL)

    return {
        "services": service_statuses,
        "high_dlq_depth": high_depth,
        "low_dlq_depth": low_depth,
        "high_queue_depth": high_queue_depth,
        "low_queue_depth": low_queue_depth,
        "events": events,
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
