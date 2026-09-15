Ruby DNS Load Balancing

Overview: Pass a gRPC target starting with dns:/// as the first argument to Temporalio::Client.connect to enable round-robin across resolved IPs.

Example:

client = Temporalio::Client.connect("dns:///your-endpoint:7233", "your-namespace")

Client.connect usage with address as first positional argument appears in the Ruby client docs.

See core concept: references/core/dns-load-balancing.md
