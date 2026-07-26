# Python SDK Payload and Memo Size Validation

> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.
>

The Temporal Service rejects payloads above its blob size limit (default 2 MB) and rejects gRPC messages above 4 MB.
Without validation, an oversized payload returned from an Activity or scheduled by a Workflow Task is uploaded to the server and rejected, which historically left workflows stuck or terminated depending on where the payload originated.

The Python SDK validates payload and memo sizes against server-reported error limits **before** sending data to the server. When a size exceeds the limit, the worker fails the current Workflow Task with cause `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`; the Workflow Execution stays open so the operator can deploy a fix.

## Default behavior

Validation is on by default starting in `temporalio` 1.23.0.
`Worker(..., disable_payload_error_limit=False, ...)` is the default — no code change is required to get the protection.

The worker fetches the per-namespace error limits from the server. If the server doesn't report limits, the worker doesn't enforce them.

## Warning thresholds — `PayloadLimitsConfig`

Configure warning thresholds on the `DataConverter` to log when payloads or memo size cross a soft limit, separately from the server-enforced error limit:

```python
import dataclasses
from temporalio.client import Client
from temporalio.converter import DataConverter, PayloadLimitsConfig

data_converter = dataclasses.replace(
    DataConverter.default,
    payload_limits=PayloadLimitsConfig(
        payload_size_warning=256 * 1024,  # bytes
        memo_size_warning=4 * 1024,       # bytes
    ),
)

client = await Client.connect(
    "localhost:7233",
    data_converter=data_converter,
)
```

Field reference:

- `payload_size_warning: int` — bytes; defaults to `512 * 1024`.
- `memo_size_warning: int` — bytes; defaults to `2 * 1024`.

`PayloadLimitsConfig` is a frozen dataclass.

## Warning class

When a payload or aggregate memo exceeds a warning threshold (but not the server error limit), the SDK issues a `PayloadSizeWarning`, which subclasses `RuntimeWarning`.

Filter or surface it with the standard `warnings` module:

```python
import warnings
from temporalio.converter import PayloadSizeWarning

warnings.simplefilter("always", PayloadSizeWarning)
```

## Disabling enforcement — `Worker(disable_payload_error_limit=...)`

```python
from temporalio.worker import Worker

worker = Worker(
    client,
    task_queue="my-task-queue",
    workflows=[...],
    activities=[...],
    disable_payload_error_limit=True,
)
```

Set to `True` only when a gRPC proxy between the worker and the server modifies payload bytes after the worker has measured them — for example, a proxy that compresses or re-encodes payloads — so that the worker's pre-upload size measurement no longer reflects what the server will see.

## Effect on errors

When validation rejects a task:

- The worker fails the Workflow Task locally with cause `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE` and never uploads the oversized data.
- The Workflow Execution remains open; once the cause is resolved (smaller payload, External Storage, etc.), the next Workflow Task succeeds.

## Reducing oversized data

Validation surfaces the problem earlier; it does not raise the limit. To handle data that legitimately exceeds 2 MB, offload to External Storage (claim-check pattern). See `references/python/data-handling.md` for the Payload Converter and Payload Codec, and `docs/develop/python/best-practices/data-handling/external-storage.mdx` for the built-in S3 driver and custom driver interface.

## Gotchas

- **`PayloadLimitsConfig` configures warnings only; error limits come from the server.** Setting `payload_size_warning` smaller than the server's error limit gives early visibility; it does not lower the enforcement threshold.
- **`_PayloadSizeError` is private.** The leading underscore is a stability signal — don't catch it by name. Workflow Task failure is observed through standard Temporal error events.
- **Server must report limits for enforcement to engage.** A worker connected to a server that doesn't report payload/memo error limits behaves as if validation were disabled.
- **Don't conflate the 2 MB payload limit with the 4 MB gRPC message limit.** Eager validation covers per-payload and aggregate memo size against server-reported limits; it does not protect against a Workflow Task whose combined commands exceed the 4 MB gRPC frame. Break large batches of commands into smaller batches.
