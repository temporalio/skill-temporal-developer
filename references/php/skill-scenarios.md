# PHP Skill Application Scenarios

Run these as retrieval/application checks when updating the PHP references. Ask a fresh reviewer to solve them using only the skill first, then check resulting API usage against the locked SDK/source. Do not mark a live workflow test passed on the strength of this review.

## Scenarios and acceptance criteria

1. **Worker with DI:** Provide minimal registration/config/start commands for an Activity with a logger dependency. Must launch through RoadRunner, pass a class plus factory to `registerActivity()`, keep Task Queue/namespace/address aligned, and distinguish logical worker concurrency from PHP pool size. Must not use `registerActivity(new ...)` or `memory_limit` as a Temporal pool option.
2. **100,000-item multi-tenant batch:** Each item has three sequential Activities; items run concurrently. Must bound page size, in-flight promises, retained outputs and history; preserve cursor/state across Continue-As-New; propagate cancellation; isolate/reset tenant context even after failure. Must explain that more pollers do not create more PHP execution capacity.
3. **PHPUnit fakes and replay:** Explain Laravel dispatch fakes versus real-worker ActivityMocker versus recorded-history replay. Must use exact registered Activity names and shared RPC/KV/converter, identify SDK 2.16 versus 2.18 environment differences, and use `Temporal\Testing\Replay\WorkflowReplayer` with a WorkflowExecution including Run ID for server replay. Must not invent factory start/stop methods or treat a printed replay failure as successful CI.
4. **Messages and continuation:** A Signal arrives while batch persistence yields; an Update is accepted but still executing. Must preserve new Signals, use a re-evaluated handler-finished predicate, preserve pending inputs, distinguish acceptance from completion, assign per-request Update IDs and test the Run ID transition. Queries/validators must remain read-only and nonblocking.
5. **Terminal payment failure and cancellation:** Must show a non-retryable ApplicationFailure with correct positional details, inspect ActivityFailure wrappers, distinguish Activity retries from workflow retries, register idempotent compensation before uncertain side effects, and use detached cleanup. Must recognize SDK Saga already detaches, explain the default TryCancel race with ongoing side effects, choose waiting/cooperative cancellation and/or external fencing/reconciliation, and decide cancellation outcome deliberately.
6. **Source adaptation traps:** Explain why course pins, Python tuning APIs, “memory never returns,” optional support attributes and the course's incomplete schedule command cannot be adopted as universal PHP requirements. Must find the pinned lesson/source map and integration constraints.

## Baseline recorded before the 2026-09-06 update

A separate agent read all 11 original PHP references. It produced `registerActivity(new OrderActivity($logger))` from the guide, could only assemble unbounded fan-out, and could not find tenant-lifetime guidance. It found unsupported test lifecycle/replay signatures, generator methods declared `string`/`void`, incomplete message-draining guidance, and handwritten cancellation cleanup without detached scopes. These were retrieval/application failures in the existing instructions, not executed PHP workflow failures.

## Validation scope

Re-run the scenarios after editing. Also lint PHP fences with the target PHP version, check local reference links and confirm nontrivial SDK calls against source or reflection. Any snippets depending on external Temporal/RoadRunner services require a separate runtime test before claiming they execute end to end. Preserve that distinction in the delivery report.

## Results for the 2026-09-06 update

- All six scenarios passed the separate agent's final retrieval/application review after corrections, including the late-payment cancellation race.
- All 48 PHP fences passed `php -l` on PHP 8.4. Seven workflow-body fragments were placed in a generator function for syntax checking; missing application contracts/imports were not runtime-tested.
- Twenty-two API/reflection/value checks passed with the available SDK v2.16.0 runtime, including registration, converters, failure details, schedules, deployment options and replay signatures. Newer APIs were checked against the pinned v2.18 source, not a v2.18 service stack.
- Local Markdown links and pinned repository paths resolved; YAML examples parsed; changed/new files passed whitespace checks.
- The generic skill-creator validator rejects the repository's pre-existing top-level `version` field on both original and updated `SKILL.md`. Temporary copies excluding that repository extension pass. The actual version field remains intact because the release workflow uses it.

No live Temporal/RoadRunner workflow run, historical replay execution, course Docker stack or framework integration suite was performed. Those remain required when applying these patterns to an application.
