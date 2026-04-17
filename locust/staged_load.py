"""
staged_load.py — Multi-stage load test for the Distributed Trading Risk Monitor.

Stages
------
  1. Ramp to   100 users over 30 s, hold 2 min
  2. Ramp to   500 users over 30 s, hold 3 min
  3. Ramp to  1000 users over 30 s, hold 3 min
  4. Ramp to  2000 users over 30 s, hold 3 min
  5. Ramp to  3000 users over 30 s, hold 3 min
  6. Cool-down: ramp to 0 over 1 min

Total runtime: ~17.5 minutes
HTML report:   written to staged_report.html automatically (no extra flag needed).

Usage
-----
  locust -f staged_load.py --host=http://<ALB_DNS>
  # headless:
  locust -f staged_load.py --host=http://<ALB_DNS> --headless --csv=staged
"""

import random
from locust import HttpUser, LoadTestShape, between, events, task

# ---------------------------------------------------------------------------
# Constants (identical to locustfile.py)
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
    """Write HTML report to staged_report.html unless --html was already given."""
    opts = getattr(environment, "parsed_options", None)
    if opts is not None and not getattr(opts, "html", None):
        opts.html = "staged_report.html"
        print("[config] HTML report will be written to staged_report.html", flush=True)

# ---------------------------------------------------------------------------
# User behaviour (same task weights and payload as locustfile.py)
# ---------------------------------------------------------------------------

class TraderUser(HttpUser):
    """
    Simulates a trader submitting transactions.
    Task weights are 6 : 3 : 1  (low : medium : high value) so the
    high-priority queue stays lightly loaded while the low-priority queue
    builds up under heavy traffic — matching the production scenario.
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

# Each row: (elapsed_secs_at_end_of_stage, target_users, spawn_rate, label)
#
# Ramp spawn_rate = Δusers / 30s (rounded up to whole number).
# Hold spawn_rate is set high so Locust doesn't try to change the count.
# Cool-down: 3000 users ÷ 50 users/s = 60 s to reach 0.

_STAGES = [
    #  end_t  users   rate   label
    (   30,    100,     4,  "Stage 1 ▶  ramp  →   100 users"),
    (  150,    100,   100,  "Stage 1 ■  hold      100 users  (2 min)"),
    (  180,    500,    14,  "Stage 2 ▶  ramp  →   500 users"),
    (  360,    500,   500,  "Stage 2 ■  hold      500 users  (3 min)"),
    (  390,   1000,    17,  "Stage 3 ▶  ramp  →  1000 users"),
    (  570,   1000,  1000,  "Stage 3 ■  hold     1000 users  (3 min)"),
    (  600,   2000,    34,  "Stage 4 ▶  ramp  →  2000 users"),
    (  780,   2000,  2000,  "Stage 4 ■  hold     2000 users  (3 min)"),
    (  810,   3000,    34,  "Stage 5 ▶  ramp  →  3000 users"),
    (  990,   3000,  3000,  "Stage 5 ■  hold     3000 users  (3 min)"),
    ( 1050,      0,    50,  "Stage 6 ▶  cool-down →  0 users  (1 min)"),
]


class StagedLoadShape(LoadTestShape):
    """
    Drives the test through the stages defined in _STAGES.
    Prints a timestamped line to stdout on every stage transition.
    Returns None once all stages are complete, which stops the test.
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
                    print(f"\n[{mm:02d}:{ss:02d}] {label}\n", flush=True)
                return (users, rate)

        # All stages finished — signal Locust to stop the test.
        return None
