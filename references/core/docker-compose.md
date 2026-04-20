# Running Temporal with Docker Compose

## Overview

Docker Compose provides a convenient way to run a Temporal development environment as a set of containers. This is an alternative to installing the Temporal CLI locally and running `temporal server start-dev`.

All examples in this guide work with both **Docker Compose** and **Podman Compose**. Simply replace `docker compose` with `podman compose` in all commands. The `compose.yaml` file format is the same for both runtimes.

This approach is especially useful when:

- You want a reproducible, self-contained dev environment
- You are running multiple services (workers, frontends) that connect to Temporal
- You want to simulate a production-like setup locally

## Minimal Compose File

A minimal `compose.yaml` to run Temporal for development:

```yaml
services:
  temporal:
    image: temporalio/temporal
    ports:
      - "7233:7233"   # gRPC frontend (used by workers and clients)
      - "8233:8233"   # Dev Server web UI
    command: server start-dev --ip 0.0.0.0
    healthcheck:
      test: ["CMD-SHELL", "temporal operator cluster health"]
      interval: 10s
      timeout: 10s
      retries: 3
```

Start it with:

```bash
docker compose up -d
# or with Podman:
podman compose up -d
```

The Temporal Web UI is then available at `http://localhost:8233`.

## Key Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 7233 | gRPC | Frontend service — workers and clients connect here |
| 8233 | HTTP | Dev Server web UI for inspecting workflows |

## Connecting Workers to Temporal in Docker Compose

Workers running as containers in the same Compose network connect to `temporal:7233` (using the service name as hostname). Workers running on the host machine connect to `localhost:7233`.

### Worker as a Compose Service

```yaml
services:
  temporal:
    image: temporalio/temporal
    ports:
      - "7233:7233"
      - "8233:8233"
    command: server start-dev --ip 0.0.0.0
    healthcheck:
      test: ["CMD-SHELL", "temporal operator cluster health"]
      interval: 10s
      timeout: 10s
      retries: 3

  worker:
    build:
      context: ./worker
    environment:
      - TEMPORAL_ADDRESS=temporal:7233
    restart: on-failure
    depends_on:
      temporal:
        condition: service_healthy
```

Important points:

- **`depends_on` with `service_healthy`** ensures the worker does not start until Temporal is ready to accept connections. Without this, the worker will crash-loop on startup.
- **`restart: on-failure`** lets the worker recover from transient errors.
- **`TEMPORAL_ADDRESS`** is the standard environment variable used by Temporal SDKs and CLI to locate the Temporal frontend service.

## Using Podman Instead of Docker

Podman is a daemonless, rootless container engine that is a drop-in replacement for Docker. Podman Compose reads the same `compose.yaml` format.

### Usage

Replace `docker compose` with `podman compose` in all commands:

```bash
podman compose up -d          # Start all services
podman compose down            # Stop and remove all services
podman compose logs -f worker  # Follow worker logs
podman compose ps              # List running services
```

### Podman-Specific Notes

- **Rootless networking**: Podman runs rootless by default. Containers in the same Compose project share a network and can reach each other by service name, just like Docker.
- **`podman-compose` vs `docker compose`**: `podman-compose` is a standalone Python tool. Alternatively, if `podman` is aliased to `docker`, the `docker compose` CLI plugin also works with Podman.
- **Healthchecks**: Podman supports healthchecks and `depends_on: condition: service_healthy` the same way as Docker Compose.
- **Build support**: `podman compose build` uses Buildah under the hood. Dockerfiles work without modification.

## Tips

- **Always use the healthcheck** on the Temporal service and `depends_on: condition: service_healthy` on workers. Without this, workers will fail to connect on startup.
- **Use `--ip 0.0.0.0`** in the Temporal dev server command so it listens on all interfaces, not just localhost. This is required for other containers to connect.
- **The `temporalio/temporal` image** bundles the Temporal CLI and runs the dev server. It is meant for development, not production. For production self-hosted deployments, use the `temporalio/auto-setup` image with a real database (PostgreSQL or MySQL).
- **Namespace creation**: The dev server creates a `default` namespace automatically. For custom namespaces, use `temporal operator namespace create` after the server is healthy.
- **Data persistence**: By default the dev server stores data in memory. Data is lost when the container is recreated. To persist data across restarts, mount a volume for the database file or use a dedicated database service.
