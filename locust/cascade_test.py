"""
cascade_test.py — Cascading failure experiment for the Distributed Trading Risk Monitor.

Stages
------
  1. Baseline   : Ramp to 200 users over 30 s, hold 3 min  — steady state before any kills
  2. Failure    : Hold 200 users for 7 min                  — kill & observe high-priority services
  3. Recovery   : Hold 200 users for 5 min                  — restore services, watch recovery
  4. Cool-down  : Ramp to 0 over 30 s

Total runtime: ~16 minutes

Kill/Restore timing
-------------------
  ~03:30  → run: ./chaos.sh kill        (kills fraud + risk + compliance)
  ~08:30  → run: ./chaos.sh restore     (brings them back)

Usage
-----
  locust -f cascade_test.py --host=http://<ALB_DNS> --headless --csv=cascade --html=cascade_report.html
"""

import random
from locust import HttpUser, LoadTestShape, between, events, task

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

TRANSACTION_TYPES = ["purchase", "withdrawal", "transfer", "deposit"]
CURRENCIES        = ["USD", "EUR", "GBP", "JPY"]
MERCHANTS         = [f"merchant_{i:03d}" for i in range(1, 11)]
USER_IDS          = [f"user_{i:04d}" for i in range(1, 101)]

# ---------------------------------------------------------------------------
# HTML report — enabled by default
# ---------------------------------------------------------------------------

@events.init.add_listener
def configure_html_report(environment, **kwargs):
    opts = getattr(environment, "parsed_options", None)
    if opts is not None and not getattr(opts, "html", None):
        opts.html = "cascade_report.html"
        print("[config] HTML report → cascade_report.html", flush=True)

# ---------------------------------------------------------------------------
# User behaviour (identical to locustfile.py)
# ---------------------------------------------------------------------------

class TraderUser(HttpUser):
    """
    Simulates a trader submitting transactions.
    Task weights 6:3:1 (low : medium : high value) keep the high-priority
    queue lightly loaded while the low-priority queue builds under load.
    """

    wait_time = between(0.05, 0.5)

    @task(6)
    def submit_low_value_transaction(self):
        amount = round(random.uniform(10.0, 999.99), 2)
        self._post_transaction(amount)

    @task(3)
    def submit_medium_value_transaction(self):
        amount = round(random.uniform(1_000.0, 9_999.99), 2)
        self._post_transaction(amount)

    @task(1)
    def submit_high_value_transaction(self):
        user_id = f"user_{random.randint(1, 10):04d}"
        amount  = round(random.uniform(10_000.0, 100_000.0), 2)
        self._post_transaction(
            amount,
            user_id=user_id,
            tx_type=random.choice(["withdrawal", "transfer"]),
        )

    def _post_transaction(self, amount: float, user_id: str = None, tx_type: str = None):
        payload = {
            "user_id":          user_id or random.choice(USER_IDS),
            "amount":           amount,
            "currency":         random.choice(CURRENCIES),
            "merchant_id":      random.choice(MERCHANTS),
            "transaction_type": tx_type or random.choice(TRANSACTION_TYPES),
        }
        with self.client.post(
            "/transaction",
            json=payload,
            catch_response=True,
            name="/transaction",
        ) as resp:
            if resp.status_code == 202:
                resp.success()
            else:
                resp.failure(
                    f"Expected 202 Accepted, got {resp.status_code}: {resp.text[:200]}"
                )

# ---------------------------------------------------------------------------
# Load shape
# ---------------------------------------------------------------------------
#
# Each row: (elapsed_secs_at_end_of_stage, target_users, spawn_rate, label)
#
# Stage 1 ramp:     200 users / 30 s = spawn_rate 7
# Stage 4 cooldown: 200 users / 30 s = spawn_rate 7 (ramp down)
# Hold stages use a high spawn_rate so Locust doesn't drift the count.
#
# Timeline                         elapsed
#   Stage 1 ramp  (0   → 30s)         0 – 30
#   Stage 1 hold  (30s → 3m30s)       30 – 210
#   Stage 2 hold  (3m30s → 10m30s)   210 – 630   ← KILL at ~03:30, RESTORE at ~08:30
#   Stage 3 hold  (10m30s → 15m30s)  630 – 930
#   Stage 4 ramp  (15m30s → 16m)     930 – 960

_STAGES = [
    #  end_t  users  rate  label
    (   30,    200,    7,  "STAGE 1: BASELINE — ramp to 200 users"),
    (  210,    200,  200,  "STAGE 1: BASELINE — holding 200 users (3 min)"),
    (  630,    200,  200,  "STAGE 2: FAILURE WINDOW — holding 200 users (7 min) | RUN: ./chaos.sh kill"),
    (  930,    200,  200,  "STAGE 3: RECOVERY — holding 200 users (5 min) | RUN: ./chaos.sh restore"),
    (  960,      0,    7,  "STAGE 4: COOL-DOWN — ramping to 0"),
]


class CascadeLoadShape(LoadTestShape):
    """
    Drives the cascading failure experiment through four distinct stages.
    Prints a timestamped banner to stdout at every stage transition.
    Returns None when all stages complete, stopping the test.
    """

    def __init__(self):
        super().__init__()
        self._last_stage_idx = -1

    def tick(self):
        run_time = self.get_run_time()

        for idx, (end_t, users, rate, label) in enumerate(_STAGES):
            if run_time < end_t:
                if idx != self._last_stage_idx:
                    self._last_stage_idx = idx
                    mm = int(run_time // 60)
                    ss = int(run_time % 60)
                    print(f"\n{'=' * 60}", flush=True)
                    print(f"  [{mm:02d}:{ss:02d}]  {label}", flush=True)
                    print(f"{'=' * 60}\n", flush=True)
                return (users, rate)

        return None
