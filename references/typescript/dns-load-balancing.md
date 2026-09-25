TypeScript DNS Load Balancing

Overview: To spread RPCs across multiple A/AAAA records for a hostname, pass a gRPC target starting with dns:/// in Connection.connect options.

Example:

Connection.connect({ address: dns:///your-endpoint:7233 })

The address field comes from the TypeScript client docs.

See core concept: references/core/dns-load-balancing.md
