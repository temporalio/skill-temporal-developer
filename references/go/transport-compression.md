# Go — Transport Compression

Default behavior

- The Go SDK enables gzip transport compression by default. If an RPC/method does not support compressed requests, the client retries the call without compression.

Opt out

- Set client options to disable transport compression entirely:

Example (structure only; adapt to your setup):

- opts := client.Options{ ConnectionOptions: client.ConnectionOptions{ GrpcCompression: &client.GrpcCompressionNone{} } }
- c, err := client.Dial(ctx, serverAddr, &opts)

Citations

- Default gzip and auto-downgrade behavior — go-sdk: client/client.go (GrpcCompressionGzip comment)
- Option types — go-sdk: client/options (GrpcCompressionGzip, GrpcCompressionNone)
