# Go SDK External Storage

> **Pre-Release.** External Storage is in Pre-Release. APIs and configuration
> may change before the stable release. Join the `#large-payloads` Slack
> channel to provide feedback or ask for help. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:14-20 -->

The Temporal Service enforces a 2 MB per-payload limit by default. This limit
is configurable on self-hosted deployments only (Cloud is fixed at 2 MB).
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:22-23 -->
When your Workflows or Activities handle data larger than the limit, you can
offload payloads to external storage such as Amazon S3 and pass a small
reference token through the Event History instead.
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:22-25 -->

For the concept-level overview (lifecycle, claim check pattern, data pipeline),
see `references/core/external-storage.md`. For the Python SDK equivalent, see
`references/python/external-storage.md`.

## Store and retrieve large payloads with Amazon S3

The Go SDK includes an S3 storage driver. Amazon S3 is the only built-in
driver documented for Go. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:31 -->

### Prerequisites

- An Amazon S3 bucket that you have read and write access to. Refer to
  lifecycle management to ensure that your payloads remain available for the
  entire lifetime of the Workflow.
  <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:35-36 -->
- Install the S3 driver module and its dependencies:

  ```
  go get go.temporal.io/sdk/contrib/aws/s3driver go.temporal.io/sdk/contrib/aws/s3driver/awssdkv2 github.com/aws/aws-sdk-go-v2/config github.com/aws/aws-sdk-go-v2/service/s3
  ```
  <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:37 -->

### Create the S3 storage driver

Load AWS configuration and create the driver. The driver uses your standard
AWS credentials from the environment (environment variables, IAM role, or AWS
config file).
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:41 -->

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
<!-- SNIPSTART go-s3-driver-create; docs/develop/go/best-practices/data-handling/external-storage.mdx:43-61 -->

### Wire the driver on the Client

Configure the driver on `converter.ExternalStorage` and pass it via
`client.Options.ExternalStorage` when dialing.
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:63 -->

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
<!-- SNIPSTART go-s3-external-storage-setup; docs/develop/go/best-practices/data-handling/external-storage.mdx:65-81 -->

All Workflows and Activities running on the Worker use the storage driver
automatically without changes to your business logic. The driver uploads and
downloads payloads concurrently and validates payload integrity on retrieve.
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:87-88 -->

## Configure payload size threshold

By default, payloads larger than 256 KiB are offloaded to external storage.
Adjust this via the `PayloadSizeThreshold` option on `converter.ExternalStorage`.
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:231-233 -->

Go-specific quirks:

- `PayloadSizeThreshold: 0` is interpreted as the default 256 KiB. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:233 -->
- `PayloadSizeThreshold: 1` externalizes all payloads regardless of size. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:232-233 -->

```go
c, err := client.Dial(client.Options{
	ExternalStorage: converter.ExternalStorage{
		Drivers:              []converter.StorageDriver{driver},
		PayloadSizeThreshold: 1,
	},
})
```
<!-- SNIPSTART go-external-storage-threshold; docs/develop/go/best-practices/data-handling/external-storage.mdx:235-245 -->

## Implement a custom storage driver

If you need a storage backend other than what the built-in driver allows,
implement your own. Store payloads durably so that they survive process
crashes and remain available for debugging and auditing after the Workflow
completes.
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:92-94 -->

The following example uses local disk and is for local development and
testing only. Production code should use a durable backend accessible to all
Workers.
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:96-97 -->

```go
type LocalDiskStorageDriver struct {
	storeDir string
}

func NewLocalDiskStorageDriver(storeDir string) converter.StorageDriver {
	return &LocalDiskStorageDriver{storeDir: storeDir}
}

func (d *LocalDiskStorageDriver) Name() string {
	return "my-local-disk"
}

func (d *LocalDiskStorageDriver) Type() string {
	return "local-disk"
}

func (d *LocalDiskStorageDriver) Store(
	ctx converter.StorageDriverStoreContext,
	payloads []*commonpb.Payload,
) ([]converter.StorageDriverClaim, error) {
	dir := d.storeDir
	switch info := ctx.Target.(type) {
	case converter.StorageDriverWorkflowInfo:
		if info.WorkflowID != "" {
			dir = filepath.Join(d.storeDir, info.Namespace, info.WorkflowID)
		}
	case converter.StorageDriverActivityInfo:
		// StorageDriverActivityInfo is only used for standalone (non-workflow-bound)
		// activities. Activities started by a workflow use StorageDriverWorkflowInfo.
		if info.ActivityID != "" {
			dir = filepath.Join(d.storeDir, info.Namespace, info.ActivityID)
		}
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("create store directory: %w", err)
	}

	claims := make([]converter.StorageDriverClaim, len(payloads))
	for i, payload := range payloads {
		key := uuid.NewString() + ".bin"
		filePath := filepath.Join(dir, key)

		data, err := proto.Marshal(payload)
		if err != nil {
			return nil, fmt.Errorf("marshal payload: %w", err)
		}
		if err := os.WriteFile(filePath, data, 0o644); err != nil {
			return nil, fmt.Errorf("write payload: %w", err)
		}

		claims[i] = converter.StorageDriverClaim{
			ClaimData: map[string]string{"path": filePath},
		}
	}
	return claims, nil
}

func (d *LocalDiskStorageDriver) Retrieve(
	ctx converter.StorageDriverRetrieveContext,
	claims []converter.StorageDriverClaim,
) ([]*commonpb.Payload, error) {
	payloads := make([]*commonpb.Payload, len(claims))
	for i, claim := range claims {
		filePath := claim.ClaimData["path"]
		data, err := os.ReadFile(filePath)
		if err != nil {
			return nil, fmt.Errorf("read payload: %w", err)
		}
		payload := &commonpb.Payload{}
		if err := proto.Unmarshal(data, payload); err != nil {
			return nil, fmt.Errorf("unmarshal payload: %w", err)
		}
		payloads[i] = payload
	}
	return payloads, nil
}
```
<!-- SNIPSTART go-custom-storage-driver; docs/develop/go/best-practices/data-handling/external-storage.mdx:99-179 -->

### The `converter.StorageDriver` interface (four methods)

A custom driver implements `converter.StorageDriver` with four methods.
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:185 -->

- `Name() string` returns a unique string identifying the driver **instance**.
  The SDK stores this name in the claim check reference so it can route
  retrieval requests to the correct driver. Changing the name after payloads
  are stored breaks retrieval. Example: `"s3-primary"` vs. `"s3-archive"`.
  <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:187-189 -->
- `Type() string` returns a string identifying the driver **implementation**.
  Unlike `Name()`, this must be the same across all instances of the same
  driver type regardless of configuration. Two S3 drivers named
  `"s3-primary"` and `"s3-archive"` would both return `"aws.s3driver"`; the
  local disk driver above returns `"local-disk"`.
  <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:190-192 -->
- `Store(ctx converter.StorageDriverStoreContext, payloads []*commonpb.Payload) ([]converter.StorageDriverClaim, error)`
  receives a slice of payloads and returns one `StorageDriverClaim` per
  payload. A claim is a set of string key-value pairs that the driver uses to
  locate the payload later.
  <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:193-194 -->
- `Retrieve(ctx converter.StorageDriverRetrieveContext, claims []converter.StorageDriverClaim) ([]*commonpb.Payload, error)`
  receives the claims that `Store()` produced and returns the original
  payloads. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:195 -->

Name (per-instance) and Type (per-implementation) are **not** synonyms.
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:187-192 -->

### The `ctx.Target` type switch

`ctx.Target` is one of:

- `converter.StorageDriverWorkflowInfo` — provides `Namespace` and
  `WorkflowID`. Activities started by a workflow use this variant.
  <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:124-127 -->
- `converter.StorageDriverActivityInfo` — used **only** for standalone
  (non-workflow-bound) activities. Activities started by a workflow do not
  see this variant; they receive `StorageDriverWorkflowInfo`.
  <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:128-133 -->

Use a type switch on `ctx.Target` to access the concrete identity fields, and
consider structuring storage keys so you can identify which Workflow owns
each payload. <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:204-207 -->

### Store and Retrieve mechanics

In `Store()`, marshal each `*commonpb.Payload` to bytes with
`proto.Marshal(payload)` and write the bytes to your storage system. The
application data has already been serialized by the Payload Converter and
Payload Codec before it reaches the driver.
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:199-202 -->

Return one `converter.StorageDriverClaim{ClaimData: map[string]string{...}}`
per payload, with enough information in `ClaimData` to retrieve it later.
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:152-154, 193-194 -->

In `Retrieve()`, download the bytes using the claim data, then reconstruct
the protobuf message with `proto.Unmarshal(data, payload)`. The Payload
Converter handles deserializing the application data after the driver
returns the payload.
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:211-213 -->

### Configure the Client with your custom driver

```go
c, err := client.Dial(client.Options{
    ExternalStorage: converter.ExternalStorage{
        Drivers: []converter.StorageDriver{NewLocalDiskStorageDriver("/tmp/temporal-payload-store")},
    },
})
```
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:219-225 -->

You can also package your driver as a plugin for easier reuse across services.
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:227 -->

## Use multiple storage drivers

When you register multiple drivers, provide a `DriverSelector` that
implements the `StorageDriverSelector` interface. The selector chooses which
driver stores each payload. Any driver in the list that is not selected for
storing is still available for retrieval — useful when migrating between
storage backends.
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:249-252 -->

Returning `nil` from the selector keeps that specific payload **inline** in
Event History (it does **not** mean "externalize").
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:251-252 -->

The `StorageDriverSelector` interface requires a single method:

```go
SelectDriver(ctx converter.StorageDriverStoreContext, payload *commonpb.Payload) (converter.StorageDriver, error)
```
<!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:273-278 -->

Motivating scenarios from the docs:

- **Driver migration.** Your Worker needs to retrieve payloads created by
  clients that use a different driver than the one you prefer. Register both
  drivers and use the selector to always pick your preferred driver for new
  payloads. The old driver remains available for retrieving existing claims.
  <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:256-258 -->
- **Multi-cloud storage.** Route payloads to different storage backends
  based on your cloud environment — for example, S3 for Workers on AWS and
  GCS for Workers on Google Cloud. The selector chooses the appropriate
  driver based on the runtime environment.
  <!-- docs/develop/go/best-practices/data-handling/external-storage.mdx:259-261 -->

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
<!-- SNIPSTART go-external-storage-multiple-drivers; docs/develop/go/best-practices/data-handling/external-storage.mdx:266-287 -->
