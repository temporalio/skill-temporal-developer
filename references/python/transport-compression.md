# Python — Transport Compression

Default behavior

- The Python SDK enables GZIP transport compression by default.

Opt out

- Disable transport compression when connecting the client:

- client = await Client.connect(target_host=..., grpc_compression=GrpcCompression.NONE)

Notes

- Transport compression is distinct from payload compression via data converters.
