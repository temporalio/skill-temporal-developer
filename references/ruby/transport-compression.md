# Ruby — Transport Compression

Default behavior

- The Ruby SDK enables gzip transport compression by default.

Opt out

- Disable transport compression when connecting:

- Temporalio::Client.connect(target_host: host:7233, grpc_compression: Temporalio::Client::Connection::GrpcCompressionOptions::None.new)

Notes

- Transport compression is separate from payload compression.
