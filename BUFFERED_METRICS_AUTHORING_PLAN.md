# Skill Authoring Plan — `buffered-metrics` (TypeScript)

**Mode:** greenfield

**Context:** The TypeScript SDK has gained support for the `UpDownCounter` instrument type in both buffered metrics and `RuntimeMetricMeter`. This topic is narrow — it concerns one SDK (TypeScript), one feature area (custom metric meter / buffered metrics), and one specific instrument type (`UpDownCounter`) added alongside the previously supported `Counter`, `Histogram`, and `Gauge` instruments. The audience is a developer using `@temporalio/worker`'s `Runtime.install({ telemetryOptions })` who wants to plug in a custom metric meter (e.g. for emitting Temporal SDK metrics through their own OpenTelemetry pipeline or in-process aggregator) or who is buffering metrics for later draining. Sibling skills: `skill-temporal-cli` (CLI) and `skill-temporal-triage` (incident triage). Neither covers SDK telemetry; everything stays in `skill-temporal-developer`.

---

## 1. Source of truth

**Primary (authoritative):** the local clone of `temporalio/documentation` at `../documentation/`.

Relevant paths:

- `docs/develop/typescript/platform/observability.mdx` — TypeScript SDK observability entry point. Covers `Runtime.install`, `telemetryOptions`, the `metrics: { otel: { url } }` and `metrics: { prometheus: { bindAddress } }` options. Does **not** currently mention buffered metrics, `RuntimeMetricMeter`, custom metric meters, or any instrument-type list. This gap is the primary risk.
- `docs/references/sdk-metrics.mdx` — Catalog of metric names emitted by the SDKs. Useful for grounding the *list of instrument types Temporal itself emits* (Counter, Histogram, Gauge) but does not describe the TypeScript custom-metric-meter API surface.
- `docs/develop/dotnet/platform/observability.mdx` — Sibling SDK reference. Shows the equivalent .NET concept (`CustomMetricMeter` on `TemporalRuntime.Telemetry.Metrics`). Useful only as a conceptual analogue; do not transcribe .NET names into TypeScript.

**Secondary (only if primary is silent):**

- The TypeScript SDK API reference at `typescript.temporal.io/api/` (specifically `worker.Runtime`, `worker.TelemetryOptions`, and any `MetricMeter` / `MetricSink` / instrument-related symbols). This is the *only* source of truth for the actual API names because the documentation clone is silent. Cite as `<!-- ts-api: <symbol> -->` rather than as a `docs/` path.
- The `temporalio/sdk-typescript` repository's CHANGELOG and `packages/worker/src/runtime.ts` / `packages/core-bridge/` source for instrument-type enums, if reachable.

Prefer Read/Grep on the local clone over WebFetch. Check `../` for sibling clones before reaching for the network. **Crucial caveat for this topic:** the docs clone does not document this feature, so most concrete claims must either come from `typescript.temporal.io/api/` or carry a `<!-- VERIFY -->` marker.

**Never trust:** any prior sketch of buffered-metrics APIs, names like `BufferedMetricSink`, `RuntimeMetricsBuffer`, `MetricInstrumentType`, etc. unless verified against the SDK API reference or source. The shape of "buffered" in the topic description could mean *(a)* a sink that buffers metric updates for later drain by user code, or *(b)* a runtime-internal aggregation buffer for batched export. Until verified, treat the noun as ambiguous and prefer descriptive prose over concrete API surface.

---

## 3. Methodology — the verification protocol

Follow this protocol for **every** factual claim you write. No exceptions.

### 3.1 The grep-first rule

Before writing a flag name, command, enum, error string, env var, or API shape, open the relevant docs file and confirm it is present verbatim. Use Grep with the exact token. Do **not** paraphrase from memory.

Example workflow for "what `metrics` options does `Runtime.install` accept?":

1. `Read ../documentation/docs/develop/typescript/platform/observability.mdx` §"Emit metrics".
2. Transcribe only what appears in that file — currently `metrics: { otel: { url } }` and `metrics: { prometheus: { bindAddress } }`.
3. Record the line number (`observability.mdx:39–40`).
4. For anything *not* present (custom meter, buffered, UpDownCounter), do not invent the option key. Either consult `typescript.temporal.io/api/` and cite `<!-- ts-api: ... -->`, or leave a `<!-- VERIFY: actual telemetryOptions key for custom meter -->`.

### 3.2 Citation/provenance format

Use HTML comments. Pick *one* convention per file and use it consistently:

```markdown
`metrics: { prometheus: { bindAddress } }` <!-- docs/develop/typescript/platform/observability.mdx:40 -->
`Runtime.install` <!-- ts-api: worker.Runtime#install -->
`UpDownCounter` <!-- VERIFY: confirm instrument-type name vs. typescript.temporal.io/api -->
```

Source-category tagging is **on** for this topic because the docs clone is silent and most claims will come from the SDK API reference rather than `docs/`:

```markdown
`metrics: { otel: { url } }` <!-- docs/develop/typescript/platform/observability.mdx:39 -->
`Runtime.install` <!-- ts-api: worker.Runtime#install -->
`UpDownCounter` <!-- ts-api: <verified-symbol> -->
```

### 3.3 Anti-fabrication rules (generic)

Refuse each of these patterns explicitly:

1. **No "probably exists" commands/subcommands.** If it's not in the docs or the SDK API reference, it doesn't exist.
2. **No "probably accepts" enum values.** Only list instrument types confirmed against the SDK API.
3. **No "probably named" env vars, fields, or options keys.** Transcribe from the authoritative source.
4. **No inferred names.** Don't derive `metrics: { buffered: {} }` from "buffered metrics" if the actual key is something else. Name-shape plausibility is not evidence.
5. **No conflating concept with interface.** "Buffered metrics" is a feature/concept name; the actual TypeScript option/class names may differ. Document the interface token; name the concept separately.
6. **No flattening of instrument types.** If the SDK distinguishes `Counter` from `UpDownCounter`, don't write "Counter (can go down)".
7. **No assumed defaults.** Don't write "default: Counter" unless the API reference says so.

### 3.4 Anti-fabrication rules (topic-specific)

- **Do not pluralize "UpDownCounter" as "UpDownCounters" inside a method/type name** unless the API shows that form. The OpenTelemetry spec uses `UpDownCounter` singular for the instrument type and `createUpDownCounter` for the factory.
- **Do not assume `add` vs. `record` vs. `update` is the method name** on the instrument. Counters typically use `add` (with positive deltas); UpDownCounters typically use `add` (with signed deltas); Histograms use `record`; Gauges use `set`. Confirm against the actual SDK before naming the method.
- **Do not assume value type.** `UpDownCounter` may take `number` (JS number) or `bigint`; do not write a type without checking.
- **Do not assume label/attribute key shape.** OpenTelemetry calls them "attributes"; older Temporal SDK metric code used "tags". Pick the term the TypeScript API actually uses.
- **Do not conflate buffered metrics with Prometheus or OTel options.** Prometheus and OTel exporters are *output sinks owned by the SDK*. Buffered metrics is a mechanism for user code to receive metric updates programmatically. Confusing them produces wrong configuration examples.
- **Do not infer the option key for a custom meter from `.NET`'s `CustomMetricMeter`.** The TypeScript key may be `customMetricMeter`, `metricMeter`, `meter`, or something else entirely.

### 3.5 When the docs are ambiguous or silent

For this topic the docs clone is *silent on the core feature*. Options in order of preference:

1. Consult the TypeScript SDK API reference at `typescript.temporal.io/api/` and cite `<!-- ts-api: ... -->`.
2. Consult `temporalio/sdk-typescript` source (e.g. `packages/worker/src/runtime.ts`) and cite `<!-- ts-source: <path> -->`.
3. Note the ambiguity in `<!-- VERIFY: ... -->` and leave the claim out of the prose. An empty section with a VERIFY note is acceptable; a fabricated section is not.

### 3.6 Stay descriptive, not prescriptive-beyond-docs

Where the upstream describes what a thing does, describe what that thing does. Where the upstream doesn't prescribe a workflow, don't invent one. The single recipe in this skill — "wire an UpDownCounter for an in-process gauge of in-flight requests" — must chain documented facts, and every step must cite the source the fact comes from.

---

## 5. Per-file execution order

This is a narrow feature addition, not a full skill rewrite. Layout:

1. **`references/typescript/buffered-metrics.md`** — new dedicated reference. Sections:
   - What buffered metrics and `RuntimeMetricMeter` are (one paragraph, concept-level, cited).
   - Supported instrument types: `Counter`, `Histogram`, `Gauge`, **`UpDownCounter`** (new). Each line cited; explicit note that `UpDownCounter` is the addition being documented here.
   - Minimal setup snippet showing where the custom meter plugs into `Runtime.install({ telemetryOptions: { metrics: { ... } } })`. Use `<!-- VERIFY -->` markers for the specific option key until confirmed against `typescript.temporal.io/api`.
   - When to use `UpDownCounter` vs. `Counter` (signed deltas; gauge-like values that you want to *increment/decrement* rather than *set*).
   - Common mistakes (see §8).
   Ground truth: `typescript.temporal.io/api/` (primary for API shape); `docs/develop/typescript/platform/observability.mdx` (for the `Runtime.install` / `telemetryOptions` framing already in the skill).

2. **`references/typescript/observability.md`** — append a single one-line pointer under the existing "Metrics" section: `For custom metric meters (buffered metrics, RuntimeMetricMeter, supported instrument types including UpDownCounter), see references/typescript/buffered-metrics.md.` No other edits to this file.

`SKILL.md` is **not** updated. The skill's "Additional Topics" section already directs readers to `references/{your_language}/observability.md`, and the pointer added in step 2 carries them forward.

Why this order matters: `buffered-metrics.md` must establish the concept and the instrument-type list before any cross-link is added, so a reader following the pointer from `observability.md` lands on a self-contained page.

---

## 6. Per-file done criteria

A reference file is done when:

1. Every API symbol (class, method, option key, instrument-type name) appears verbatim in either `docs/`, `typescript.temporal.io/api/`, or the SDK source — or carries a `<!-- VERIFY -->` marker with a specific question.
2. Every name/token has a citation comment in one of the formats from §3.2.
3. The instrument-type list is exhaustive against the SDK API reference (no "probably also supports X").
4. No option key appears in a snippet that isn't traceable to an authoritative source.
5. A self-check Grep finds zero instances of the regression patterns listed in §8.

---

## 7. Deliverables

At the end of authoring, produce:

- **`AUTHORING_LOG.md`** at the skill root: for each reference file, sources consulted, citation count, every `<!-- VERIFY -->` marker raised with the question and why it remains open.
- **A git-visible diff** — one logical change per file (`references/typescript/buffered-metrics.md` new; `references/typescript/observability.md` single-line cross-link added).

Do not create files outside `references/` and the skill root. No `docs/` subdirectories, tutorials, `CONTRIBUTING.md`, or meta-docs.

---

## 8. Regression patterns

| Wrong pattern | Should be | Source |
|---|---|---|
| Listing only `Counter`, `Histogram`, `Gauge` as supported instrument types | Include `UpDownCounter` as the fourth supported type | (topic premise; `info.json` description) |
| `metrics: { buffered: {...} }` invented option key | Use the actual `telemetryOptions.metrics.*` key from the TS API reference; otherwise leave `<!-- VERIFY -->` | ts-api: worker.TelemetryOptions |
| Treating `UpDownCounter` as a synonym for `Counter` ("counter that can go down") | Distinct instrument type with **signed deltas** via the same `add(value, attributes)` shape OpenTelemetry uses | ts-api: <verified-symbol> |
| Calling `record()` on an `UpDownCounter` | OpenTelemetry instrument convention: counters/up-down-counters expose `add`; histograms expose `record`; gauges expose `set` (or observable callback) — confirm against TS API before writing the method name | ts-api / OTel spec |
| Cross-using .NET `CustomMetricMeter` shape (constructor takes a `Meter`) in TS examples | Document only the TS shape from the TS API | docs/develop/dotnet/platform/observability.mdx:67 (analogue, not transcription) |
| "UpDownCounter (added in SDK vX.Y)" with an invented version number | Either cite the SDK CHANGELOG entry or omit the version | sdk-typescript CHANGELOG |
| Conflating buffered metrics with Prometheus/OTel exporters | Buffered metrics = user-owned meter receives metric updates; Prometheus/OTel = SDK-owned exporter | docs/develop/typescript/platform/observability.mdx:39–40 |

This table is the input to the validation plan's Check 3 (regression). Keep it in sync.

---

## 9. Known correct anchors

- `Runtime.install` is the single entry point for installing telemetry options (`docs/develop/typescript/platform/observability.mdx:37`, linking to `https://typescript.temporal.io/api/classes/worker.Runtime/#install`).
- `metrics: { otel: { url } }` and `metrics: { prometheus: { bindAddress } }` are the two output-sink options currently documented (`docs/develop/typescript/platform/observability.mdx:39–40`).
- `TelemetryOptions` is the interface name in the TS API (`docs/develop/typescript/platform/observability.mdx:37`, linking to `https://typescript.temporal.io/api/interfaces/worker.TelemetryOptions`).
- The SDK Metrics reference catalogs metric **names** emitted by the SDK and tags them by metric type (`Counter`, `Histogram`) but does not enumerate the *instrument types* the user-side meter API supports (`docs/references/sdk-metrics.mdx:87–101`).
- Core-based SDKs (TypeScript, Python, .NET) share the same Rust Core for telemetry, and Core defines the worker metric set (`docs/references/sdk-metrics.mdx:42, 49`).
- .NET exposes a *custom metric meter* slot under `Telemetry.Metrics.CustomMetricMeter` (`docs/develop/dotnet/platform/observability.mdx:67–87`). This is the conceptual analogue. **Do not transcribe the .NET names into TypeScript.**

---

## 10. Non-goals

- **Do not re-architect the skill.** Keep the file layout, section order, and `SKILL.md` frontmatter schema as-is.
- **Do not expand scope.** This skill covers buffered metrics + `RuntimeMetricMeter` + the `UpDownCounter` instrument type for TypeScript only. Don't pull in tracing, logging, Prometheus exporter tuning, or other-SDK metric meters except as one-line analogues for context.
- **Do not paraphrase docs prose verbatim.** Cite, don't copy.
- **Do not write tests, CI, or tooling.** This is documentation work.
- **Do not add meta-docs** (`CHANGELOG.md`, `CONTRIBUTING.md`, `ROADMAP.md`).
- **Do not bloat `SKILL.md` or the language entry-point file.** No per-topic pointer at root or in `references/typescript/typescript.md` — the cross-link from `observability.md` is sufficient.

End of plan.
