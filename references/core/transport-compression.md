
# Transport Compression (gRPC)

Temporal SDKs use gRPC for client connections. Transport compression is per-RPC message compression performed by gRPC. Most SDKs now default to gzip and offer an option to disable it. Some SDKs automatically retry the RPC without compression if a method/endpoint does not support it.

[!NOTE]
This is different from payload compression via data converters or a codec server. Payload compression affects the encoded payloads inside a request/response; transport compression affects the gRPC frames on the wire. The 4 MB per-message gRPC limit still applies regardless of transport compression.

## Defaults and opt-out, by language

- Go — Default gzip; retries uncompressed if unsupported. Opt out via GrpcCompressionNone in client.Options.
- Java — Default GZIP; opt out with ServiceStubsOptions#setGrpcCompression(GrpcCompression.NONE).
- Python — Default GZIP; opt out with Client.connect(..., grpc_compression=GrpcCompression.NONE).
- .NET — Default Gzip; opt out with TemporalConnectionOptions.GrpcCompression = GrpcCompression.None.
- Ruby — Default gzip; opt out with grpc_compression: Temporalio::Client::Connection::GrpcCompressionOptions::None.new.
- TypeScript — Default enabled; opt out with grpcCompression: { codec: none } on connection options.

## Guidance

- Prefer the default (gzip). Disable only when communicating with proxies/servers that cannot accept compressed gRPC frames.
- Do not confuse transport compression with payload compression. See references/python/data-handling.md, references/typescript/external-storage.md, and similar per-language data handling pages for payload-level patterns.

## See also

- Language-specific details and examples:
  - references/go/transport-compression.md
  - references/java/transport-compression.md
  - references/python/transport-compression.md
  - references/dotnet/transport-compression.md
  - references/ruby/transport-compression.md
  - references/typescript/transport-compression.md

