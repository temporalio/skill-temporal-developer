# gRPC transport compression

The connection options below control compression of gRPC messages on the wire. Use a payload codec to compress payloads stored in Workflow Event History. The Service still enforces its [payload size limits](gotchas.md#payload-size-limits) when transport compression is enabled.

Keep the SDK default unless a server or proxy has trouble with gzip. If a connection fails because the peer cannot decompress its requests, use the opt-out for that connection.

| SDK | Gzip by default since | Connection option to opt out |
| --- | --- | --- |
| Go | 1.45.0 | Set `client.Options.ConnectionOptions.GrpcCompression` to `&client.GrpcCompressionNone{}` when dialing. |
| Java | 1.36.0 | Call `setGrpcCompression(GrpcCompression.NONE)` on the `WorkflowServiceStubsOptions` builder. Import `io.temporal.serviceclient.GrpcCompression`. |
| Python | 1.29.0 | Pass `grpc_compression=GrpcCompression.NONE` to `Client.connect()`. Import `GrpcCompression` from `temporalio.service`. |
| .NET | 1.17.0 | Set `TemporalClientConnectOptions.GrpcCompression` to `new GrpcCompression.None()` when connecting. Import `Temporalio.Client`. |
| Ruby | 1.6.0 | Pass `grpc_compression: Temporalio::Client::Connection::GrpcCompressionOptions::None.new` to `Temporalio::Client.connect`. |
| TypeScript | 1.19.0 | Pass `grpcCompression: { codec: 'none' }` to `NativeConnection.connect()` from `@temporalio/worker`. This option applies to `NativeConnection`. |
