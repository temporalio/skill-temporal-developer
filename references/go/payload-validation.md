# Go SDK Payload Validation

Practical guide to payload size limits in the Go SDK, how oversized payloads
surface at runtime, and how to mitigate them with External Storage.

For the cross-language failure-cause enums and the general framing of payload
validation, see `references/core/payload-validation.md`.

## Size limits

The Temporal Service enforces two distinct size limits on data that passes
between the Client, Workers, and the Service:

- A **2 MB per-argument** payload limit. A single Activity argument is limited
  to a maximum size of 2 MB. <!-- docs/develop/go/activities/basics.mdx:77 -->
- A **4 MB per gRPC message** limit. The total size of a gRPC message, which
  includes all the arguments, is limited to a maximum of 4 MB. <!-- docs/develop/go/activities/basics.mdx:78 -->

The 2 MB payload limit is configurable on self-hosted deployments but is fixed
at 2 MB on Temporal Cloud. <!-- docs/troubleshooting/blob-size-limit-error.mdx:26-28 -->

Activity return values are subject to the same payload size limits, with a
default of 2 MB and a hard 4 MB gRPC message limit. <!-- docs/develop/go/activities/basics.mdx:119 -->

All Payload data is recorded in the Workflow Execution Event History, so even
payloads that stay under the per-message limit can grow Event History to a
point that affects Worker performance. <!-- docs/develop/go/activities/basics.mdx:80-81 -->

## Failure behavior in the Go SDK

The Go SDK is **not** the Python SDK 1.23.0+, which means it falls into the
"All other SDK versions" failure-behavior bucket described in the
troubleshooting docs. Outcomes depend on where the oversized payload
originates.

### Payload size limit (2 MB)

For oversized **inputs** (Workflow input, Activity input), the Temporal Service
rejects the command and **terminates the Workflow**; you must resolve the issue
and restart the Workflow. <!-- docs/troubleshooting/blob-size-limit-error.mdx:51-52 -->

For an oversized **Activity result**, the Temporal Service rejects the Activity
completion and the **Activity fails with an error**. <!-- docs/troubleshooting/blob-size-limit-error.mdx:53 -->

For an oversized **Workflow result**, the Workflow gets stuck in a retry loop:
the server rejects the `CompleteWorkflowExecution` command, and replay produces
the same oversized result. <!-- docs/troubleshooting/blob-size-limit-error.mdx:54-55 -->

The corresponding failure cause is `WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`. <!-- docs/troubleshooting/blob-size-limit-error.mdx:35 -->
Server-side error strings you may see include
`[TMPRL1103] Attempted to upload payloads with size that exceeded the error limit.`,
`BadScheduleActivityAttributes: ScheduleActivityTaskCommandAttributes.Input exceeds size limit`,
`Complete result exceeds size limit`, and
`CompleteWorkflowExecutionCommandAttributes.Result exceeds size limit`. <!-- docs/troubleshooting/blob-size-limit-error.mdx:36-40 -->

### gRPC message size limit (4 MB)

A Workflow can hit the 4 MB gRPC limit even when every individual payload is
under 2 MB; for example, scheduling several Activities with moderate-sized
inputs, or hundreds of Activities with tiny inputs, in the same Workflow Task
can push the combined request past 4 MB. <!-- docs/troubleshooting/blob-size-limit-error.mdx:91-93 -->

For oversized **Workflow Tasks**, the Workflow gets stuck in a retry loop that
isn't visible in Event History: when the Worker completes a Workflow Task it
sends all commands the Workflow produced back to the Service, the SDK catches
the gRPC error and sends a failed Workflow Task response with cause
`WORKFLOW_TASK_FAILED_CAUSE_GRPC_MESSAGE_TOO_LARGE`, and replay produces the
same oversized request every time. <!-- docs/troubleshooting/blob-size-limit-error.mdx:112-116 -->

For oversized **Activity Tasks**, the Activity gets stuck in a retry loop or
exits with a `ScheduleToCloseTimeout`. The Activity executes successfully, but
the Worker can't deliver the oversized result over gRPC, so the server retries.
If no `ScheduleToCloseTimeout` is set, the Activity retries indefinitely until
the Workflow is manually terminated; the `ResourceExhausted` gRPC error only
appears in Worker logs. <!-- docs/troubleshooting/blob-size-limit-error.mdx:118-123 -->

## Mitigation: External Storage in the Go SDK

> External Storage is in **Pre-Release**. APIs and configuration may change
> before the stable release. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:14-20 -->

External Storage offloads payloads to an external store (such as Amazon S3) and
passes a small reference token through Event History instead. This is the
documented mitigation pattern for the 2 MB per-payload limit. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:22-25 -->

**Important:** `PayloadSizeThreshold` is the offload threshold for External
Storage, not a validation limit. The server's 2 MB error limit still applies;
External Storage avoids tripping that limit by uploading large payloads to your
store and sending only the claim check through gRPC. To get the equivalent of
"fail fast before hitting the server limit," configure a
`PayloadSizeThreshold` below 2 MB so qualifying payloads are offloaded before
they can be rejected.

### Install the S3 driver

Install the S3 driver module and its dependencies: <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:37 -->

```sh
go get go.temporal.io/sdk/contrib/aws/s3driver go.temporal.io/sdk/contrib/aws/s3driver/awssdkv2 github.com/aws/aws-sdk-go-v2/config github.com/aws/aws-sdk-go-v2/service/s3
```

You also need an Amazon S3 bucket that you have read and write access to. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:35-36 -->

### Construct the driver

The driver uses your standard AWS credentials from the environment (environment
variables, IAM role, or AWS config file). <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:41 -->

```go
cfg, err := config.LoadDefaultConfig(context.Background(),
	config.WithRegion("us-east-2"),
)
if err != nil {
	log.Fatalf("load AWS config: %v", err)
}

driver, err := s3driver.NewDriver(s3driver.Options{
	Client: awssdkv2.NewClient(s3.NewFromConfig(cfg)),
	Bucket: s3driver.StaticBucket("my-temporal-payloads"),
})
if err != nil {
	log.Fatalf("create S3 driver: %v", err)
}
```
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:45-60 -->

### Wire the driver on the Client

Configure the driver on `ExternalStorage` and pass it in your Client options. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:63 -->

```go
c, err := client.Dial(client.Options{
	HostPort: "localhost:7233",
	ExternalStorage: converter.ExternalStorage{
		Drivers: []converter.StorageDriver{driver},
	},
})
if err != nil {
	log.Fatalf("connect to Temporal: %v", err)
}
defer c.Close()

w := worker.New(c, "my-task-queue", worker.Options{})
```
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:67-80 -->

All Workflows and Activities running on the Worker use the storage driver
automatically without changes to your business logic. The driver uploads and
downloads payloads concurrently and validates payload integrity on retrieve. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:87-88 -->

### `PayloadSizeThreshold` semantics

By default, payloads larger than **256 KiB** are offloaded to external
storage. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:231-232 -->
You can adjust this with the `PayloadSizeThreshold` option, or set it to **1**
to externalize all payloads regardless of size. **A value of 0 is interpreted
as the default (256 KiB).** <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:232-233 -->

```go
c, err := client.Dial(client.Options{
	ExternalStorage: converter.ExternalStorage{
		Drivers:              []converter.StorageDriver{driver},
		PayloadSizeThreshold: 1,
	},
})
```
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:238-244 -->

Again: this is the **offload threshold**, not a validation limit. Setting
`PayloadSizeThreshold: 1` externalizes every payload, which is the strongest
guarantee against tripping the 2 MB server error.

## The `StorageDriver` interface

A custom driver implements the `converter.StorageDriver` interface with four
methods: <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:185 -->

- `Name()` returns a unique string that identifies the driver instance. The SDK
  stores this name in the claim check reference so it can route retrieval
  requests to the correct driver. Changing the name after payloads have been
  stored breaks retrieval. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:187-189 -->
- `Type()` returns a string that identifies the driver implementation. Unlike
  `Name()`, this must be the same across all instances of the same driver type
  regardless of configuration. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:190-192 -->
- `Store()` receives a slice of payloads and returns one `StorageDriverClaim`
  per payload. A claim is a set of string key-value pairs that the driver uses
  to locate the payload later. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:193-194 -->
- `Retrieve()` receives the claims that `Store()` produced and returns the
  original payloads. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:195 -->

In `Store()`, marshal each Payload protobuf message to bytes with
`proto.Marshal(payload)` and write the bytes to your storage system. The
application data has already been serialized by the Payload Converter and
Payload Codec before it reaches the driver. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:199-202 -->

In `Retrieve()`, download the bytes using the claim data, then reconstruct the
Payload protobuf message with `proto.Unmarshal(data, payload)`. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:211-213 -->

The `ctx.Target` field provides identity information (namespace, Workflow ID)
depending on the operation. Use a type switch on `StorageDriverWorkflowInfo`
and `StorageDriverActivityInfo` to access the concrete values. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:204-206 -->

## Using multiple storage drivers

When you register multiple drivers, you must provide a `DriverSelector` that
implements the `StorageDriverSelector` interface. The selector chooses which
driver stores each payload. Any driver in the list that is not selected for
storing is still available for retrieval, which is useful when migrating
between storage backends. Return `nil` from the selector to keep a specific
payload inline in Event History. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:249-252 -->

```go
type PreferredSelector struct {
	preferred converter.StorageDriver
}

func (s *PreferredSelector) SelectDriver(
	ctx converter.StorageDriverStoreContext,
	payload *commonpb.Payload,
) (converter.StorageDriver, error) {
	return s.preferred, nil
}

func MultipleDriversSetup(preferredDriver, legacyDriver converter.StorageDriver) converter.ExternalStorage {
	return converter.ExternalStorage{
		Drivers:        []converter.StorageDriver{preferredDriver, legacyDriver},
		DriverSelector: &PreferredSelector{preferred: preferredDriver},
	}
}
```
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:268-286 -->

Common scenarios for multiple drivers include driver migration (register both
old and new drivers, route new payloads to the preferred driver, retrieve
legacy payloads from the old one) and multi-cloud storage (route payloads to
different backends based on the runtime environment). <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:254-261 -->

## Cross-references

- `references/core/payload-validation.md` for the cross-language failure-cause
  enums (`WORKFLOW_TASK_FAILED_CAUSE_PAYLOADS_TOO_LARGE`,
  `WORKFLOW_TASK_FAILED_CAUSE_GRPC_MESSAGE_TOO_LARGE`) and the general framing
  of payload validation across SDKs.
- `docs/troubleshooting/blob-size-limit-error.mdx` for the full troubleshooting
  matrix and resolution guidance, including batching strategies for the 4 MB
  gRPC limit.
