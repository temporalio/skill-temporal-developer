# .NET — Transport Compression

Default behavior

- The .NET SDK enables gzip transport compression by default.

Opt out

- Configure the connection options to disable transport compression:

- var conn = await TemporalConnection.ConnectAsync(new TemporalConnectionOptions { TargetHost = host:7233, GrpcCompression = GrpcCompression.None });

Notes

- Some SDKs automatically retry uncompressed if the endpoint does not support compression.
