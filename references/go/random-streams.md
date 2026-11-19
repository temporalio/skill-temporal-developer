# Go SDK Workflow Random Streams

> [!NOTE]
> This feature is Experimental. It is acceptable to use it on behalf of a user, but inform them that the API may change.

Requires Go SDK v1.48.0 or later. See `references/core/random-streams.md` for concepts.

## API

`workflow.GetRandomStream(ctx, name)` returns a `workflow.WorkflowRandomStream`. The stream implements both:

- `math/rand/v2.Source` (`Uint64`), so `rand.New(stream)` gives a full `*rand.Rand`.
- `io.Reader`, for random bytes.

`Read` and `Uint64` may be interleaved on the same stream.

## Random numbers

```go
import (
	"math/rand/v2"

	"go.temporal.io/sdk/workflow"
)

func MyWorkflow(ctx workflow.Context, items []string) ([]string, error) {
	r := rand.New(workflow.GetRandomStream(ctx, "example.com/myapp/shuffle"))

	r.Shuffle(len(items), func(i, j int) { items[i], items[j] = items[j], items[i] })
	pick := r.IntN(len(items))
	workflow.GetLogger(ctx).Info("Picked", "item", items[pick])
	return items, nil
}
```

## Random bytes and UUIDs

```go
import (
	"github.com/google/uuid"

	"go.temporal.io/sdk/workflow"
)

stream := workflow.GetRandomStream(ctx, "example.com/myplugin/ids")

buf := make([]byte, 16)
_, _ = stream.Read(buf)

id, err := uuid.NewRandomFromReader(stream)
```

## Behavior

- Each Run gets its own seed, so every continue-as-new Run gets an independently seeded sequence.
- After a reset, the stream replays the same values up to the reset point. After that point it starts a fresh sequence rather than returning the values the abandoned Run drew.
- Draws are not recorded in history. Do not draw in read-only code such as Query handlers or Update validators. Shared code can check `workflow.IsReadOnly(ctx)`.

## Instead of

- `math/rand` or `math/rand/v2` top-level functions in Workflow code: these are non-deterministic.
- `workflow.SideEffect` for random values: each call adds a marker event to history, which bloats Event History. `GetRandomStream` provides the random values without adding any events.
- A hand-rolled PRNG seeded from `workflow.GetInfo(ctx)`: use `GetRandomStream` instead.
