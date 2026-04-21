# Cadence Development Management

## Local Development Loop

Typical loop:

1. Run a Cadence server locally or connect to a dev environment.
2. Register or select a domain.
3. Start workers for the task lists your workflows use.
4. Start workflows with the Cadence CLI or application code.
5. Inspect histories, signals, queries, and visibility results.

## CLI Basics

Show top-level help:

```bash
cadence --help
```

Describe a domain:

```bash
cadence --domain <domain> domain describe
```

Start a workflow:

```bash
cadence --domain <domain> workflow start \
  --tl <task-list> \
  --wt <workflow-type> \
  --et 3600
```

## Worker Management

Workers must poll the same task list names your client code uses.

When debugging workflow dispatch problems, verify:

- Domain
- Task list name
- Registered workflow type
- Registered activities

## Visibility Management

For search-heavy workflows:

- Use memo for non-indexed display data
- Use search attributes for indexed query data
- Confirm allowlisting and advanced visibility support in the target environment

## Deployment Safety

Before deploying workflow code changes:

1. Identify whether replayed command order changes.
2. Add `GetVersion` or create a new workflow type if needed.
3. Test replay compatibility.
4. Roll out workers carefully.

## Domain And Multi-Cluster Concepts

Cadence uses domains as the main logical boundary. Some deployments also use global domains and cross-DC replication. Keep operational guidance aligned with your actual server topology.
