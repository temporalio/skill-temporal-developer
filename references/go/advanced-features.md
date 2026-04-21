# Cadence Go Advanced Features

## Distributed Cron

Cadence supports distributed cron style recurring execution.

Prefer Cadence cron support over Temporal Schedule API examples.

## Async Activity Completion

Cadence supports asynchronous activity completion patterns for activities that must return later from outside the worker process.

## Sessions And Replay Tools

Cadence Go also provides sessions and replay/shadowing related capabilities in the broader official docs. Use them when your codebase already depends on them.

## Scope Note

This file intentionally excludes Temporal-only Go features such as Schedule APIs and Worker Versioning.
