# AWS S3 External Storage (Python)

Use the Python SDK S3 storage driver to offload large payloads to Amazon S3 and pass only a small reference through Event History. See the External Storage concept page for background and lifecycle guidance. https://docs.temporal.io/external-storage

- Install extra: python -m pip install "temporalio[aioboto3]".
- Create an aioboto3 client and pass it to S3StorageDriver; credentials come from standard AWS sources.
- Configure the driver on a DataConverter via ExternalStorage and pass it to Client and Worker.
- Default offload threshold is 256 KiB; set payload_size_threshold to 0 to externalize all payloads.
- Temporal does not delete objects; configure an S3 lifecycle policy with TTL long enough for Workflow lifetime plus namespace retention.
- For multi-region durability, you may use S3 Multi-Region Access Points and configure the driver accordingly.

Related references:
- Python External Storage guide: https://docs.temporal.io/develop/python/data-handling/external-storage
- External Storage concept: https://docs.temporal.io/external-storage
- Blob and message size limits plus claim check: https://docs.temporal.io/troubleshooting/blob-size-limit-error
