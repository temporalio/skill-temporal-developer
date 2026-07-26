# Go SDK Payload and Memo Size Validation

> [!NOTE]
> This feature is in Public Preview. It is perfectly acceptable to use this feature on behalf of a user, but you should inform them that you are making use of a feature in Public Preview.
>

The Temporal Service rejects payloads above its blob size limit (default 2 MB) and rejects gRPC messages above 4 MB.
Without validation, an oversized payload returned from an Activity or scheduled by a Workflow Task is uploaded to the server, gets rejected, and the workflow may end up stuck in a retry loop or terminated depending on where the payload originated.

The Go SDK validates payload and memo sizes against server-reported error limits **before** sending data to the server. When a size exceeds the limit, the worker fails the current Task locally — the Workflow Execution stays open so the operator can deploy a fix.

## Default behavior

`DisablePayloadErrorLimit` defaults to `false`, so validation is on by default.
The worker fetches the per-namespace error limits from the server. If the server doesn't report limits, the worker doesn't enforce them.

No code change is required to get the default protection — just upgrade the SDK to v1.43.0 or later.

## Warning thresholds — `client.PayloadLimitOptions`

Set warning thresholds on the Client to emit a log when individual payloads or aggregated memo size cross a soft limit, separately from the server-enforced error limit:

```go
import "go.temporal.io/sdk/client"

c, err := client.Dial(client.Options{
    PayloadLimits: client.PayloadLimitOptions{
        PayloadSizeWarning: 256 * 1024, // bytes
        MemoSizeWarning:    4 * 1024,   // bytes
    },
})
```

Field reference:

- `PayloadSizeWarning int` — bytes; zero/unset defaults to 512 KiB.
- `MemoSizeWarning int` — bytes; zero/unset defaults to 512 KiB.

Warnings are logged via the configured logger; they do not fail tasks.

## Disabling enforcement — `worker.Options.DisablePayloadErrorLimit`

```go
import "go.temporal.io/sdk/worker"

w := worker.New(c, "task-queue", worker.Options{
    DisablePayloadErrorLimit: true,
})
```

Set to `true` only when a gRPC proxy between the worker and the server modifies payload bytes after the worker has measured them — for example, a proxy that compresses or re-encodes payloads — so that the worker's pre-upload size measurement no longer reflects what the server will see.

## Effect on errors

When validation rejects a task:

- The worker fails the Workflow Task or Activity Task locally and never uploads the oversized data.
- The Workflow Execution remains open; the task is eligible for retry after the user reduces payload size, switches to External Storage, or otherwise resolves the cause.
- Without validation, oversized inputs cause `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`; oversized Workflow results historically caused a server-side retry loop.

## Reducing oversized data

Validation surfaces the problem earlier; it does not raise the limit. To handle data that legitimately exceeds 2 MB, offload to External Storage (claim-check pattern). See `references/go/data-handling.md` for the Payload Converter and Payload Codec, and `docs/develop/go/best-practices/data-handling/external-storage.mdx` for the built-in S3 driver and custom driver interface.

## Gotchas

- **Set `PayloadLimits` on the Client, not the Worker.** Warning thresholds are part of `client.Options`. The Worker option is the opt-out only.
- **Server must report limits for enforcement to engage.** A worker connected to a server that doesn't report payload/memo error limits behaves as if validation were disabled.
- **Don't conflate the 2 MB payload limit with the 4 MB gRPC message limit.** Eager validation covers the per-payload and aggregate memo size against server-reported limits; it does not protect against a Workflow Task whose combined commands exceed the 4 MB gRPC frame. Break large batches of commands into smaller batches.
