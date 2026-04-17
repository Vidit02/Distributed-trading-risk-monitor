"""
CAP theorem experiment — multi-region load test.

Fires a fixed transaction payload at one or two ALB endpoints (primary/west and
optional secondary/east) and prints per-region count / avg / p50 / p95 latency
at shutdown. Pair with the risk service running in single/local/dual-write
sync modes to see the consistency-vs-latency tradeoff show up in real numbers.
"""

import os
import time
import random
import statistics
import requests
from locust import HttpUser, task, between, events

# Populated from --east-host on test_start. Empty string → single-region mode.
EAST_HOST = ""

# Per-region response times in milliseconds.
response_times = {"west": [], "east": []}
request_counts = {"west": 0, "east": 0}

FIXED_PAYLOAD = {
    "user_id": "region-test-user-001",
    "amount": 1000.00,
    "currency": "USD",
    "merchant_id": "merchant_cap_test",
    "transaction_type": "withdrawal",
}


@events.init_command_line_parser.add_listener
def _(parser):
    parser.add_argument(
        "--east-host",
        type=str,
        default="",
        help="Secondary (east) region host URL, e.g. http://east-alb.example.com. "
             "When set, ~50%% of traffic is sent here directly instead of the "
             "primary host — for running the CAP theorem experiment.",
    )


@events.test_start.add_listener
def on_test_start(environment, **_kwargs):
    global EAST_HOST
    EAST_HOST = (environment.parsed_options.east_host or "").rstrip("/")
    if EAST_HOST:
        print(f"[region-test] DUAL-REGION mode — west={environment.host} east={EAST_HOST}")
    else:
        print(f"[region-test] SINGLE-REGION mode — west={environment.host} only")


@events.test_stop.add_listener
def on_test_stop(**_kwargs):
    print("\n=== CAP EXPERIMENT — PER-REGION LATENCY ===")
    for region in ("west", "east"):
        samples = response_times[region]
        count = request_counts[region]
        if not samples:
            print(f"  {region.upper():5s}: count=0  (no requests)")
            continue
        avg = statistics.fmean(samples)
        p50 = _percentile(samples, 50)
        p95 = _percentile(samples, 95)
        print(
            f"  {region.upper():5s}: count={count:<6d} "
            f"avg={avg:7.2f}ms  p50={p50:7.2f}ms  p95={p95:7.2f}ms"
        )
    print("===========================================\n")


def _percentile(values, pct):
    # nearest-rank percentile — avoids numpy dependency.
    ordered = sorted(values)
    k = max(0, min(len(ordered) - 1, int(round(pct / 100.0 * len(ordered))) - 1))
    return ordered[k]


class RegionTestUser(HttpUser):
    """Short wait + fixed payload → fast burst for CAP latency observation."""

    wait_time = between(0.01, 0.05)

    @task
    def submit_transaction(self):
        if EAST_HOST and random.random() < 0.5:
            self._post_east()
        else:
            self._post_west()

    def _post_west(self):
        start = time.time()
        with self.client.post(
            "/transaction",
            json=FIXED_PAYLOAD,
            catch_response=True,
            name="/transaction [WEST]",
        ) as resp:
            elapsed_ms = (time.time() - start) * 1000.0
            response_times["west"].append(elapsed_ms)
            request_counts["west"] += 1
            if resp.status_code == 202:
                resp.success()
            else:
                resp.failure(
                    f"Expected 202 Accepted, got {resp.status_code}: {resp.text[:200]}"
                )

    def _post_east(self):
        url = f"{EAST_HOST}/transaction"
        start = time.time()
        exception = None
        response_length = 0
        try:
            resp = requests.post(url, json=FIXED_PAYLOAD, timeout=10)
            response_length = len(resp.content or b"")
            if resp.status_code != 202:
                exception = Exception(
                    f"Expected 202 Accepted, got {resp.status_code}: {resp.text[:200]}"
                )
        except Exception as e:  # requests.RequestException, timeouts, etc.
            exception = e

        elapsed_ms = (time.time() - start) * 1000.0
        response_times["east"].append(elapsed_ms)
        request_counts["east"] += 1

        # Report to Locust's stats pipeline so it shows up in the UI / CSV.
        events.request.fire(
            request_type="POST",
            name="/transaction [EAST]",
            response_time=elapsed_ms,
            response_length=response_length,
            exception=exception,
            context={},
        )
