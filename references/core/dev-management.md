# Development Server and Worker Management

## Server Management

Before starting workers or workflows, you MUST start a local dev server, using the Temporal CLI:

```bash
temporal server start-dev # Start this in the background.
```

It is perfectly OK for this process to be shared across multiple projects / left running as you develop your Temporal code.

The dev server is in-memory by default -- all workflows, schedules, and history are lost on restart. Use `--db-filename temporal.db` to persist across restarts. <!-- docs/cli/server.mdx:69 -->

The dev server is for local development only, not production. <!-- docs/cli/server.mdx:28-35 -->

### `temporal server start-dev` flags

| Flag | Default | Purpose |
|---|---|---|
| `--db-filename`, `-f` | in-memory | Persistent SQLite file. Without it, state is in-memory and lost on exit. <!-- docs/cli/server.mdx:69 --> |
| `--namespace`, `-n` | `default` only | Namespaces to create at launch. Repeatable. The `default` namespace is always created. <!-- docs/cli/server.mdx:76 --> |
| `--search-attribute` | — | Register search attributes as `KEY=TYPE` pairs. TYPE is one of: `Text`, `Keyword`, `Int`, `Double`, `Bool`, `Datetime`, `KeywordList`. Repeatable. <!-- docs/cli/server.mdx:78 --> |
| `--port`, `-p` | `7233` | Front-end gRPC port. <!-- docs/cli/server.mdx:77 --> |
| `--ui-port` | `--port` + 1000 | Web UI port. <!-- docs/cli/server.mdx:83 --> |
| `--ip` | `127.0.0.1` | IP address bound to the front-end service. Use `0.0.0.0` for Docker/LAN access. <!-- docs/cli/server.mdx:73 --> |
| `--dynamic-config-value` | — | Dynamic config in `KEY=JSON_VALUE` form. Repeatable. <!-- docs/cli/server.mdx:70 --> |
| `--log-level` | `warn` | (Global flag) Log level. Accepted values: `debug`, `info`, `warn`, `error`, `never`. Default is `warn` for `start-dev`. <!-- docs/cli/server.mdx:109 --> |
| `--log-format` | `text` | (Global flag) Log format. Accepted values: `text`, `json`. <!-- docs/cli/server.mdx:108 --> |
| `--headless` | — | Disable the Web UI. <!-- docs/cli/server.mdx:71 --> |
| `--http-port` | random free port | HTTP API port. <!-- docs/cli/server.mdx:72 --> |
| `--metrics-port` | random free port | Prometheus `/metrics` port. <!-- docs/cli/server.mdx:75 --> |

Example with persistence, extra namespaces, and a search attribute:

```bash
temporal server start-dev \
    --db-filename /tmp/temporal.db \
    --namespace dev \
    --search-attribute OrderId=Keyword
```

<!-- Sources: docs/cli/server.mdx:23-109 -->

## Worker Management Details

### Starting Workers

How you start a worker is project-dependent, but generally Temporal code should have a program entrypoint which starts a worker. If your project doesn't, you should define it.

When you need a new worker, you should start it in the background (and preferrably have it log somewhere you can check), and then remember its PID so you can kill / clean it up later.

**Best practice**: As far as local development goes, run only ONE worker instance with the latest code. Don't keep stale workers (running old code) around.

### Cleanup

**Always kill workers when done.** Don't leave workers running.

## Dev to Prod

Steps to promote a workflow from a local dev server to a production backend. The workflow and worker code do not change between environments; only the connection descriptor does.

### 1. Start a local dev server with persistence

```bash
temporal server start-dev --db-filename dev.db
```

<!-- Sources: docs/cli/server.mdx:23-69 -->

### 2. Run the workflow against dev

Start your worker, then execute the workflow:

```bash
temporal workflow execute \
    --type MyWorkflow \
    --task-queue my-queue \
    --input '{"key": "value"}'
```

`workflow execute` blocks until the run terminates; a non-zero exit means the run failed, was cancelled, terminated, or timed out. <!-- docs/cli/workflow.mdx:159-204 -->

### 3. Create a prod stored environment

```bash
temporal env set prod.address   "your-ns.your-acct.tmprl.cloud:7233"
temporal env set prod.namespace "your-ns.your-acct"
temporal env set prod.api-key   "your-key"
```

The environment-selecting flag is `--env <name>` (env var `TEMPORAL_ENV`). <!-- docs/cli/env.mdx:27-110 -->

### 4. Smoke-test prod

```bash
temporal workflow list --env prod --limit 1
```

If this returns (even an empty list), the connection descriptor is correct. <!-- docs/cli/index.mdx:358-362 -->

### 5. Run in prod

```bash
temporal workflow start \
    --env prod \
    --type MyWorkflow \
    --task-queue my-queue \
    --input '{"key": "value"}'
```

`workflow start` is asynchronous (returns a Workflow/Run ID); use `workflow execute` instead if you want the CLI to block. <!-- docs/cli/workflow.mdx:544-582 -->

For stored environment details, see skill-temporal-ops `cli-scripting.md`.
