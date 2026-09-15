# Deterministic Random Streams (Core)

## Overview

Workflows must be deterministic on replay. Many apps and libraries need randomness but should not share a single global stream because interleaving consumes values in different orders. A named deterministic stream is an isolated pseudo-random number generator (PRNG) whose seed is derived deterministically from workflow identity and a caller-chosen stream name.

## When to Use

- Isolate plugins and libraries from the app’s default PRNG
- Implement reproducible shuffles, sampling, or tie-breaking
- Avoid cross-talk when multiple components draw random values

## Design

- Seed derivation: combine stable identifiers (for example, Workflow ID, optional Run ID, and a stream name). Hash to a 32-bit or 64-bit integer.
- PRNG choice: a small, fast PRNG (mulberry32, sfc32, xorshift) is sufficient. Do not rely on system entropy or wall-clock time.
- Determinism: keep all state in workflow memory; no I/O, no wall clock, no global process state.
- Versioning: changing the hash or PRNG changes sequences. Treat that change as a compatibility boundary for in-flight workflows.

## Choosing a Seed Scope

- Per Workflow ID: stable across retries and resets; ideal for game worlds or consistent partitioning.
- Per Run ID: unique to an execution; good for randomized backoffs or fair tie-breaks per attempt.
- Hybrid: include both Workflow ID and Run ID when you need per-execution uniqueness but still bind to the workflow identity.

## Library Guidance

- Pick a unique stream name prefix (for example, plugin:yourlib) to avoid collisions.
- Do not consume from the app’s default PRNG inside a library; always create your own named stream.
- Document your seed inputs so callers understand stability characteristics.

## Related

- TypeScript recipe: references/typescript/random-streams.md
# Deterministic Random Streams (Core)

## Overview

Workflows must be deterministic on replay. Many apps and libraries need randomness but should not share a single global stream because interleaving consumes values in different orders. A named deterministic stream is an isolated pseudo-random number generator (PRNG) whose seed is derived deterministically from workflow identity and a caller-chosen stream name.

## When to Use

- Isolate plugins and libraries from the app’s default PRNG
- Implement reproducible shuffles, sampling, or tie-breaking
- Avoid cross-talk when multiple components draw random values

## Design

- Seed derivation: combine stable identifiers (for example, Workflow ID, optional Run ID, and a stream name). Hash to a 32-bit or 64-bit integer.
- PRNG choice: a small, fast PRNG (mulberry32, sfc32, xorshift) is sufficient. Do not rely on system entropy or wall-clock time.
- Determinism: keep all state in workflow memory; no I/O, no wall clock, no global process state.
- Versioning: changing the hash or PRNG changes sequences. Treat that change as a compatibility boundary for in-flight workflows.

## Choosing a Seed Scope

- Per Workflow ID: stable across retries and resets; ideal for game worlds or consistent partitioning.
- Per Run ID: unique to an execution; good for randomized backoffs or fair tie-breaks per attempt.
- Hybrid: include both Workflow ID and Run ID when you need per-execution uniqueness but still bind to the workflow identity.

## Library Guidance

- Pick a unique stream name prefix (for example, plugin:yourlib) to avoid collisions.
- Do not consume from the app’s default PRNG inside a library; always create your own named stream.
- Document your seed inputs so callers understand stability characteristics.

## Related

- TypeScript recipe: references/typescript/random-streams.md
- Go recipe: references/go/random-streams.md
- Go recipe: references/go/random-streams.md
