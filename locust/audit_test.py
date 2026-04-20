"""
audit_test.py — Locust test that submits exactly 10,000 transactions with
sequential user IDs (audit-user-0001 … audit-user-10000) and records every
202 response to audit_submitted.csv.

Run:
    locust -f locust/audit_test.py --host http://<ALB_DNS> \
           --users 50 --spawn-rate 10 --headless

The test stops automatically once all 10,000 sequence slots are claimed.
Output: audit_submitted.csv (sequence_number, transaction_id, user_id,
                              timestamp, http_status)
"""

import csv
import os
import threading
import time

from locust import HttpUser, between, events, task

# ---------------------------------------------------------------------------
# Shared state
# ---------------------------------------------------------------------------

TOTAL = 10_000
OUTPUT_FILE = "audit_submitted.csv"

_counter_lock = threading.Lock()
_csv_lock = threading.Lock()
_next_seq = 1          # next sequence number to hand out (1-based)
_submitted = 0         # how many have completed (any HTTP status)
_csv_file = None
_csv_writer = None


def _init_csv():
    global _csv_file, _csv_writer
    _csv_file = open(OUTPUT_FILE, "w", newline="")
    _csv_writer = csv.writer(_csv_file)
    _csv_writer.writerow(["sequence_number", "transaction_id", "user_id",
                           "timestamp", "http_status"])
    _csv_file.flush()


def _write_row(seq: int, tx_id: str, user_id: str, timestamp: str, status: int):
    with _csv_lock:
        _csv_writer.writerow([seq, tx_id, user_id, timestamp, status])
        _csv_file.flush()


@events.init.add_listener
def on_locust_init(environment, **_kwargs):
    _init_csv()
    print(f"[audit_test] output file : {os.path.abspath(OUTPUT_FILE)}")
    print(f"[audit_test] total target: {TOTAL:,} transactions")
    print(f"[audit_test] user_id fmt : audit-user-XXXX (0001–{TOTAL:04d})")


@events.quitting.add_listener
def on_quitting(environment, **_kwargs):
    if _csv_file:
        _csv_file.close()
    print(f"[audit_test] done — {_submitted:,} transactions submitted, "
          f"results in {OUTPUT_FILE}")


# ---------------------------------------------------------------------------
# User
# ---------------------------------------------------------------------------

class AuditUser(HttpUser):
    """
    Each virtual user claims sequence numbers from the shared counter one at
    a time and submits a transaction.  Once all TOTAL slots are claimed the
    user calls self.environment.runner.quit() to end the test.
    """

    wait_time = between(0.05, 0.1)   # slight jitter to avoid thundering herd

    def _claim_seq(self) -> int | None:
        """Return the next sequence number, or None if all are claimed."""
        global _next_seq
        with _counter_lock:
            if _next_seq > TOTAL:
                return None
            seq = _next_seq
            _next_seq += 1
        return seq

    @task
    def submit_audit_transaction(self):
        global _submitted

        seq = self._claim_seq()
        if seq is None:
            # All slots claimed — stop this user and signal the runner.
            self.environment.runner.quit()
            return

        user_id = f"audit-user-{seq:04d}"
        payload = {
            "user_id":          user_id,
            "amount":           100.00,
            "currency":         "USD",
            "merchant_id":      "merchant_audit",
            "transaction_type": "purchase",
        }

        tx_id = ""
        timestamp = ""
        status = 0

        with self.client.post(
            "/transaction",
            json=payload,
            catch_response=True,
            name="/transaction [audit]",
        ) as resp:
            status = resp.status_code
            if resp.status_code == 202:
                try:
                    body = resp.json()
                    tx_id = body.get("transaction_id", "")
                    timestamp = body.get("timestamp", "")
                except Exception:
                    pass
                resp.success()
            else:
                resp.failure(
                    f"Expected 202, got {resp.status_code}: {resp.text[:200]}"
                )

        _write_row(seq, tx_id, user_id, timestamp, status)

        with _counter_lock:
            _submitted += 1
            done = _submitted

        if done % 500 == 0 or done == TOTAL:
            pct = done / TOTAL * 100
            print(f"[audit_test] progress: {done:,}/{TOTAL:,}  ({pct:.1f}%)")
