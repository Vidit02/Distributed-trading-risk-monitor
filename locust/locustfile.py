"""
Locust load test for the Distributed Trading Risk Monitor.

Simulates traders submitting transactions at varying amounts to exercise
both priority queues. High-value transactions hit the high-priority queue
(fraud/risk checks); low-value transactions hit the low-priority queue
(analytics/audit).
"""

import random
from locust import HttpUser, task, between

TRANSACTION_TYPES = ["purchase", "withdrawal", "transfer", "deposit"]
CURRENCIES = ["USD", "EUR", "GBP", "JPY"]
MERCHANTS = [f"merchant_{i:03d}" for i in range(1, 11)]
USER_IDS = [f"user_{i:04d}" for i in range(1, 101)]


class TraderUser(HttpUser):
    """
    Simulates a trader submitting transactions.
    Task weights are 6:3:1 (low : medium : high value) so that
    under load the high-priority queue stays lightly loaded while
    the low-priority queue builds up — matching the demo scenario.
    """

    wait_time = between(0.05, 0.5)

    # Low-value transactions
    @task(6)
    def submit_low_value_transaction(self):
        amount = round(random.uniform(10.0, 999.99), 2)
        self._post_transaction(amount)

    # Medium-value transactions
    @task(3)
    def submit_medium_value_transaction(self):
        amount = round(random.uniform(1_000.0, 9_999.99), 2)
        self._post_transaction(amount)

    # High-value transactions
    @task(1)
    def submit_high_value_transaction(self):
        user_id = f"user_{random.randint(1, 10):04d}"
        amount = round(random.uniform(10_000.0, 100_000.0), 2)
        self._post_transaction(
            amount,
            user_id=user_id,
            tx_type=random.choice(["withdrawal", "transfer"]),
        )

    def _post_transaction(self, amount: float, user_id: str = None, tx_type: str = None):
        payload = {
            "user_id": user_id or random.choice(USER_IDS),
            "amount": amount,
            "currency": random.choice(CURRENCIES),
            "merchant_id": random.choice(MERCHANTS),
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
