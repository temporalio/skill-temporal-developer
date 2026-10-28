DOTNET DNS Load Balancing

Overview: Use a gRPC target starting with dns:/// as the TargetHost in TemporalClientConnectOptions to enable round-robin across resolved IPs.

Example:

await TemporalClient.ConnectAsync(new TemporalClientConnectOptions { TargetHost = "dns:///your-endpoint:7233", Namespace = "default" });

TargetHost is shown in the .NET client docs.

See core concept: references/core/dns-load-balancing.md
