"""
risk_test.py — Locust test for the global risk-limit enforcement.

All 100 users share a single user_id (generated once at module load) so every
transaction contributes to the same user's daily Redis exposure.  With a $1,000
amount and a $50,000 daily limit, the 51st request should trigger a breach.

Run:
    locust -f locust/risk_test.py --host http://<ALB_DNS> \
           --users 100 --spawn-rate 100 --run-time 60s --headless

Use RISK_CHECK_MODE=non-atomic on the risk service to observe the race
condition: multiple requests will read the same stale total, each think
they are under the limit, and all be allowed — letting spend exceed $50k.
"""

import time

from locust import HttpUser, constant, events, task

# Shared user_id — generated once when the module is imported so every
# Locust worker in this process uses the exact same value.
SHARED_USER_ID = f"risk-test-{int(time.time())}"


@events.init.add_listener
def on_locust_init(environment, **_kwargs):
    print(f"[risk_test] shared user_id = {SHARED_USER_ID}")
    print(f"[risk_test] daily limit    = $50,000")
    print(f"[risk_test] amount/tx      = $1,000  →  breach after tx 51")


class RiskTestUser(HttpUser):
    """
    Sends $1,000 withdrawals as fast as possible, all under one user_id.
    wait_time=constant(0) means each virtual user fires the next request
    immediately after the previous one completes, maximising concurrency
    and making the non-atomic race condition clearly observable.
    """

    wait_time = constant(0)

    @task
    def submit_risk_transaction(self):
        payload = {
            "user_id":          SHARED_USER_ID,
            "amount":           10000.00,
            "currency":         "USD",
            "merchant_id":      "merchant_risk_test",
            "transaction_type": "withdrawal",
        }
        with self.client.post(
            "/transaction",
            json=payload,
            catch_response=True,
            name="/transaction [risk]",
        ) as resp:
            if resp.status_code == 202:
                resp.success()
            else:
                resp.failure(
                    f"Expected 202 Accepted, got {resp.status_code}: {resp.text[:200]}"
                )
