# Python SDK Error Handling

## Overview

The Python SDK uses `ApplicationError` for application-specific errors and provides comprehensive retry policy configuration. Generally, the following information about errors and retryability applies across activities, child workflows and Nexus operations.

## Application Errors

```python
from temporalio import activity
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
from temporalio import activity
from temporalio.exceptions import ApplicationError

@activity.defn
async def charge_card(card_number: str, amount: float) -> str:
    if not is_valid_card(card_number):
        raise ApplicationError(
            "Permanent failure - invalid credit card",
            type="PaymentError",
            non_retryable=True,  # Will not retry activity
        )
    return await process_payment(card_number, amount)
```

## Handling Activity Errors

```python
from datetime import timedelta
from temporalio import workflow
from temporalio.exceptions import ActivityError, ApplicationError

@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self) -> str:
        try:
            return await workflow.execute_activity(
                risky_activity,
                start_to_close_timeout=timedelta(minutes=5),
            )
        except ActivityError as e:
            workflow.logger.error(f"Activity failed: {e}")
            # Handle or re-raise
            raise ApplicationError("Workflow failed due to activity error")
```

## Retry Policy Configuration

```python
from datetime import timedelta
from temporalio import workflow
from temporalio.common import RetryPolicy

@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self) -> str:
        result = await workflow.execute_activity(
            my_activity,
            start_to_close_timeout=timedelta(minutes=10),
            retry_policy=RetryPolicy(
                maximum_interval=timedelta(minutes=1),
                maximum_attempts=5,
                non_retryable_error_types=["ValidationError", "PaymentError"],
            ),
        )
        return result
```

## Timeout Configuration

```python
from datetime import timedelta
from temporalio import workflow

@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self) -> str:
        return await workflow.execute_activity(
            my_activity,
            start_to_close_timeout=timedelta(minutes=5),      # Single attempt
            schedule_to_close_timeout=timedelta(minutes=30),  # Including retries
            heartbeat_timeout=timedelta(seconds=30),          # Between heartbeats
        )
```

## Workflow Failure

```python
from temporalio import workflow
from temporalio.exceptions import ApplicationError

@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self) -> str:
        if some_condition:
            raise ApplicationError(
                "Cannot process order",
                type="BusinessError",
            )
        return "success"
```

**Note:** Do not use `non_retryable=` with `ApplicationError` inside a worklow (as opposed to an activity).

## Idempotency Patterns

When Activities interact with external systems, making them idempotent ensures correctness during retries and replay.

### Using Workflow IDs as Idempotency Keys

```python
from temporalio import activity

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
from datetime import timedelta
from temporalio import workflow

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
                start_to_close_timeout=timedelta(minutes=5),
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
3. Configure appropriate retry policies
4. Log errors before re-raising
5. Use `ActivityError` to catch activity failures in workflows
6. Design code to be idempotent for safe retries (see more at `references/core/patterns.md`)
