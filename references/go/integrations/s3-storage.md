# AWS S3 External Storage (Go)

Use the Go SDK S3 storage driver to offload large payloads to Amazon S3 and pass only a small reference through Event History. See the External Storage concept page for background and lifecycle guidance. https://docs.temporal.io/external-storage

- Install packages: go.temporal.io/sdk/contrib/aws/s3driver; go.temporal.io/sdk/contrib/aws/s3driver/awssdkv2; github.com/aws/aws-sdk-go-v2/config; github.com/aws/aws-sdk-go-v2/service/s3.
- Create an AWS SDK v2 client and driver; SDK picks up credentials from environment, IAM role, or AWS config.
- Configure the driver on the Client via ExternalStorage; Workers inherit from Client.
- Default offload threshold is 256 KiB; set PayloadSizeThreshold to 1 to externalize all payloads (0 keeps the default).
- Both Client and Workers need bucket access (read/write; store also reads).
- Temporal does not delete objects; configure an S3 lifecycle policy with TTL long enough for Workflow lifetime plus namespace retention.
- For multi-region durability, you may use S3 Multi-Region Access Points and configure the driver with the MRAP ARN.

Related references:
- Go External Storage guide: https://docs.temporal.io/develop/go/data-handling/external-storage
- External Storage concept: https://docs.temporal.io/external-storage
- Blob and message size limits plus claim check: https://docs.temporal.io/troubleshooting/blob-size-limit-error
