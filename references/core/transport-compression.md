# gRPC transport compression

The connection options below control compression of gRPC messages on the wire. Use a payload codec to compress payloads stored in Workflow Event History. The Service still enforces its [payload size limits](gotchas.md#payload-size-limits) when transport compression is enabled.

The connections below use gzip by default. If a connection fails because the server or proxy cannot decompress its requests, use the opt-out for that connection.

| SDK | Connection option to opt out |
| --- | --- |
| Go | Set `client.Options.ConnectionOptions.GrpcCompression` to `&client.GrpcCompressionNone{}` when dialing. |
| Java | Call `setGrpcCompression(GrpcCompression.NONE)` on the `WorkflowServiceStubsOptions` builder. Import `io.temporal.serviceclient.GrpcCompression`. |
| Python | Pass `grpc_compression=GrpcCompression.NONE` to `Client.connect()`. Import `GrpcCompression` from `temporalio.service`. |
| .NET | Set `TemporalClientConnectOptions.GrpcCompression` to `new GrpcCompression.None()` when connecting. Import `Temporalio.Client`. |
| Ruby | Pass `grpc_compression: Temporalio::Client::Connection::GrpcCompressionOptions::None.new` to `Temporalio::Client.connect`. |
| TypeScript | Pass `grpcCompression: { codec: 'none' }` to `NativeConnection.connect()` from `@temporalio/worker`. |
