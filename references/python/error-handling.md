# Python SDK Error Handling

## Overview

The Python SDK uses `ApplicationError` for application-specific errors and provides comprehensive retry policy configuration.

## Application Errors

```python
from temporalio.exceptions import ApplicationError

@activity.defn
async def validate_order(order: Order) -> None:
    if not order.is_valid():
        raise ApplicationError(
            "Invalid order",
            type="ValidationError",
        )
```

## Non-Retryable Errors

```python
raise ApplicationError(
    "Permanent failure - invalid credit card",
    type="PaymentError",
    non_retryable=True,  # Will not retry
)
```

## Handling Activity Errors

```python
from temporalio.exceptions import ActivityError

@workflow.run
async def run(self) -> str:
    try:
        return await workflow.execute_activity(
            risky_activity,
            schedule_to_close_timeout=timedelta(minutes=5),
        )
    except ActivityError as e:
        workflow.logger.error(f"Activity failed: {e}")
        # Handle or re-raise
        raise ApplicationError("Workflow failed due to activity error")
```

## Retry Policy Configuration

```python
from temporalio.common import RetryPolicy

result = await workflow.execute_activity(
    my_activity,
    schedule_to_close_timeout=timedelta(minutes=10),
    retry_policy=RetryPolicy(
        initial_interval=timedelta(seconds=1),
        backoff_coefficient=2.0,
        maximum_interval=timedelta(minutes=1),
        maximum_attempts=5,
        non_retryable_error_types=["ValidationError", "PaymentError"],
    ),
)
```

## Timeout Configuration

```python
await workflow.execute_activity(
    my_activity,
    start_to_close_timeout=timedelta(minutes=5),      # Single attempt
    schedule_to_close_timeout=timedelta(minutes=30),  # Including retries
    heartbeat_timeout=timedelta(seconds=30),          # Between heartbeats
)
```

## Workflow Failure

```python
@workflow.run
async def run(self) -> str:
    if some_condition:
        raise ApplicationError(
            "Cannot process order",
            type="BusinessError",
            non_retryable=True,
        )
    return "success"
```

## Idempotency Patterns

When Activities interact with external systems, making them idempotent ensures correctness during retries and replay.

### Using Workflow IDs as Idempotency Keys

```python
@activity.defn
async def charge_payment(order_id: str, amount: float) -> str:
    # Use order_id as idempotency key with payment provider
    result = await payment_api.charge(
        amount=amount,
        idempotency_key=f"order-{order_id}",  # Prevents duplicate charges
    )
    return result.transaction_id
```

### Tracking Operation Status in Workflow State

```python
@workflow.defn
class OrderWorkflow:
    def __init__(self):
        self._payment_completed = False
        self._transaction_id: str | None = None

    @workflow.run
    async def run(self, order: Order) -> str:
        if not self._payment_completed:
            self._transaction_id = await workflow.execute_activity(
                charge_payment, order.id, order.total,
                schedule_to_close_timeout=timedelta(minutes=5),
            )
            self._payment_completed = True

        # Continue with order processing...
        return self._transaction_id
```

### Designing Idempotent Activities

1. **Use unique identifiers** as idempotency keys (workflow ID, activity ID, or business ID)
2. **Check before acting**: Query external system state before making changes
3. **Make operations repeatable**: Ensure calling twice produces the same result
4. **Record outcomes**: Store transaction IDs or results for verification

## Best Practices

1. Use specific error types for different failure modes
2. Mark permanent failures as non-retryable
3. Configure appropriate retry policies per activity
4. Log errors before re-raising
5. Use `ActivityError` to catch activity failures in workflows
6. Design activities to be idempotent for safe retries
