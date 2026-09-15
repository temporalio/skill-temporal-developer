# TypeScript — Transport Compression

Default behavior

- The TypeScript SDK enables gRPC gzip transport compression by default.

Opt out

- Disable transport compression on connection options:

- await NativeConnection.connect({ address: "host:7233", grpcCompression: { codec: "none" } })

Notes

- This is transport-level compression; do not confuse with payload compression patterns (claim-check, codec server).
