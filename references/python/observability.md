# Python SDK Observability

## Overview

The Python SDK provides comprehensive observability through logging, metrics, tracing, and visibility (Search Attributes).

## Logging

### Workflow Logging (Replay-Safe)

Use `workflow.logger` for replay-safe logging that avoids duplicate messages:

```python
@workflow.defn
class MyWorkflow:
    @workflow.run
    async def run(self, name: str) -> str:
        workflow.logger.info("Workflow started", extra={"name": name})

        result = await workflow.execute_activity(
            my_activity,
            schedule_to_close_timeout=timedelta(minutes=5),
        )

        workflow.logger.info("Activity completed", extra={"result": result})
        return result
```

The workflow logger automatically:
- Suppresses duplicate logs during replay
- Includes workflow context (workflow ID, run ID, etc.)

### Activity Logging

Use `activity.logger` for context-aware activity logging:

```python
@activity.defn
async def process_order(order_id: str) -> str:
    activity.logger.info(f"Processing order {order_id}")

    # Perform work...

    activity.logger.info("Order processed successfully")
    return "completed"
```

Activity logger includes:
- Activity ID, type, and task queue
- Workflow ID and run ID
- Attempt number (for retries)

### Custom Logger Configuration

```python
import logging

# Configure a custom handler
handler = logging.StreamHandler()
handler.setFormatter(logging.Formatter(
    "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
))

# Apply to Temporal's logger
temporal_logger = logging.getLogger("temporalio")
temporal_logger.addHandler(handler)
temporal_logger.setLevel(logging.INFO)
```

## Metrics

### Enabling SDK Metrics

```python
from temporalio.client import Client
from temporalio.runtime import Runtime, TelemetryConfig, PrometheusConfig

# Configure Prometheus metrics endpoint
runtime = Runtime(
    telemetry=TelemetryConfig(
        metrics=PrometheusConfig(bind_address="0.0.0.0:9090")
    )
)

client = await Client.connect(
    "localhost:7233",
    runtime=runtime,
)
```

### Key SDK Metrics

- `temporal_request` - Client requests to server
- `temporal_workflow_task_execution_latency` - Workflow task processing time
- `temporal_activity_execution_latency` - Activity execution time
- `temporal_workflow_task_replay_latency` - Replay duration

## Tracing

### OpenTelemetry Integration

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from temporalio.contrib.opentelemetry import TracingInterceptor

# Set up OpenTelemetry
provider = TracerProvider()
trace.set_tracer_provider(provider)

# Create tracing interceptor
tracing_interceptor = TracingInterceptor()

# Apply to client and worker
client = await Client.connect(
    "localhost:7233",
    interceptors=[tracing_interceptor],
)

worker = Worker(
    client,
    task_queue="my-queue",
    workflows=[MyWorkflow],
    activities=[my_activity],
    interceptors=[tracing_interceptor],
)
```

## Search Attributes (Visibility)

### Setting Search Attributes at Start

```python
from temporalio.common import SearchAttributes, SearchAttributeKey

# Define typed search attribute keys
ORDER_ID = SearchAttributeKey.for_keyword("OrderId")
CUSTOMER_TYPE = SearchAttributeKey.for_keyword("CustomerType")
ORDER_TOTAL = SearchAttributeKey.for_float("OrderTotal")

# Start workflow with search attributes
await client.execute_workflow(
    OrderWorkflow.run,
    order,
    id=f"order-{order.id}",
    task_queue="orders",
    search_attributes=SearchAttributes.from_pairs([
        (ORDER_ID, order.id),
        (CUSTOMER_TYPE, order.customer_type),
        (ORDER_TOTAL, order.total),
    ]),
)
```

### Upserting Search Attributes from Workflow

```python
@workflow.defn
class OrderWorkflow:
    @workflow.run
    async def run(self, order: Order) -> str:
        # Update status as workflow progresses
        workflow.upsert_search_attributes([
            (ORDER_STATUS, "processing"),
        ])

        await workflow.execute_activity(process_order, order, ...)

        workflow.upsert_search_attributes([
            (ORDER_STATUS, "completed"),
        ])
        return "done"
```

### Querying Workflows by Search Attributes

```python
# List workflows using search attributes
async for workflow in client.list_workflows(
    'OrderStatus = "processing" AND CustomerType = "premium"'
):
    print(f"Workflow {workflow.id} is still processing")
```

## Best Practices

1. Use `workflow.logger` in workflows, `activity.logger` in activities
2. Don't use print() in workflows - it will produce duplicate output on replay
3. Configure metrics for production monitoring
4. Use Search Attributes for business-level visibility
5. Add tracing for distributed debugging
