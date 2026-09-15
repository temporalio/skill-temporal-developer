# Go — Workflow Random Streams

## Context

The Go SDK does not ship a seeded RNG for workflows. Docs recommend using SideEffect or Activities when you need non-deterministic values recorded in history. When you want many random draws but keep determinism, create a userland PRNG seeded from deterministic workflow inputs.

## Helper: FNV-1a 32-bit seed and math/rand

~~~go
package streams

import (
    hash/fnv
    math/rand
)

// SeedFromStrings derives a 32-bit seed from stable strings, e.g., workflow ID and a stream name.
func SeedFromStrings(parts ...string) int64 {
    h := fnv.New32a()
    for _, p := range parts {
        _, _ = h.Write([]byte(p))
        _, _ = h.Write([]byte{/})
    }
    return int64(h.Sum32())
}

// NewStream returns a rand.Rand backed by its own Source.
func NewStream(seed int64) *rand.Rand {
    return rand.New(rand.NewSource(seed))
}
~~~

## Derive seeds in a Workflow

~~~go
import (
    go.temporal.io/sdk/workflow
)

type RNG interface {
    Float64() float64
    Intn(n int) int
    Shuffle(n int, swap func(i, j int))
}

type NamedStreams struct {
    App   *rand.Rand
    Lib   *rand.Rand
}

func MakeStreams(ctx workflow.Context) (*NamedStreams, error) {
    info := workflow.GetInfo(ctx)
    // Per-Workflow-ID stream
    appSeed := SeedFromStrings(info.WorkflowExecution.ID, app-default)
    // Per-Run-ID stream (changes on retry/reset)
    libSeed := SeedFromStrings(info.WorkflowExecution.ID, info.WorkflowExecution.RunID, plugin:ranker)

    return &NamedStreams{
        App: NewStream(appSeed),
        Lib: NewStream(libSeed),
    }, nil
}
~~~

## Optional: Non-deterministic root via SideEffect

If you need a non-deterministic root (for example, to decorrelate across services), capture it once with SideEffect, then derive named seeds from it.

~~~go
var root int64
encoded := workflow.SideEffect(ctx, func(workflow.Context) interface{} {
    // Any non-deterministic source; UUID or crypto/rand packaged into a value
    return time.Now().UnixNano() // example only; prefer crypto/rand if available in Activities
})
_ = encoded.Get(&root)

seed := SeedFromStrings(strconv.FormatInt(root, 10), info.WorkflowExecution.ID, app-default)
rng := NewStream(seed)
~~~

Notes
- Do not call time.Now() directly in workflows except inside SideEffect; prefer deterministic seeds from workflow identity when possible.
- Changing the hash or PRNG changes sequences; treat as a compatibility boundary.

## Related

- Concept: references/core/random-streams.md
- Determinism basics: ../documentation/docs/develop/go/workflows/basics.mdx
# Go — Workflow Random Streams

## Context

The Go SDK does not ship a seeded RNG for workflows. Docs recommend using SideEffect or Activities when you need non-deterministic values recorded in history. When you want many random draws but keep determinism, create a userland PRNG seeded from deterministic workflow inputs.

## Helper: FNV-1a 32-bit seed and math/rand

```go
package streams

import (
    "hash/fnv"
    "math/rand"
)

// SeedFromStrings derives a 32-bit seed from stable strings, e.g., workflow ID and a stream name.
func SeedFromStrings(parts ...string) int64 {
    h := fnv.New32a()
    for _, p := range parts {
        _, _ = h.Write([]byte(p))
        _, _ = h.Write([]byte{'/'})
    }
    return int64(h.Sum32())
}

// NewStream returns a rand.Rand backed by its own Source.
func NewStream(seed int64) *rand.Rand {
    return rand.New(rand.NewSource(seed))
}
```

## Derive seeds in a Workflow

```go
import (
    "go.temporal.io/sdk/workflow"
)

type RNG interface {
    Float64() float64
    Intn(n int) int
    Shuffle(n int, swap func(i, j int))
}

type NamedStreams struct {
    App   *rand.Rand
    Lib   *rand.Rand
}

func MakeStreams(ctx workflow.Context) (*NamedStreams, error) {
    info := workflow.GetInfo(ctx)
    // Per-Workflow-ID stream
    appSeed := SeedFromStrings(info.WorkflowExecution.ID, "app-default")
    // Per-Run-ID stream (changes on retry/reset)
    libSeed := SeedFromStrings(info.WorkflowExecution.ID, info.WorkflowExecution.RunID, "plugin:ranker")

    return &NamedStreams{
        App: NewStream(appSeed),
        Lib: NewStream(libSeed),
    }, nil
}
```

## Optional: Non-deterministic root via SideEffect

If you need a non-deterministic root (for example, to decorrelate across services), capture it once with SideEffect, then derive named seeds from it.

```go
var root int64
encoded := workflow.SideEffect(ctx, func(workflow.Context) interface{} {
    // Any non-deterministic source; UUID or crypto/rand packaged into a value
    return time.Now().UnixNano() // example only; prefer crypto/rand if available in Activities
})
_ = encoded.Get(&root)

seed := SeedFromStrings(strconv.FormatInt(root, 10), info.WorkflowExecution.ID, "app-default")
rng := NewStream(seed)
```

Notes
- Do not call time.Now() directly in workflows except inside SideEffect; prefer deterministic seeds from workflow identity when possible.
- Changing the hash or PRNG changes sequences; treat as a compatibility boundary.

## Related

- Concept: references/core/random-streams.md
- Determinism basics: ../documentation/docs/develop/go/workflows/basics.mdx
- Side Effects: ../documentation/docs/develop/go/workflows/side-effects.mdx
- Side Effects: ../documentation/docs/develop/go/workflows/side-effects.mdx
