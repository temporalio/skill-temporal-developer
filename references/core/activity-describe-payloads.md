# Activity Describe Payloads (Concepts)

This page explains how Describe operations for Activities surface execution metadata and, when available, offer opt-in inclusion of payloads such as input, result (also called outcome), heartbeat details, and the last failure. It focuses on when and how to request these fields and why inclusion is opt-in.

Key sources:
- CLI reference for activity describe.
- Standalone Activity example output fields.
- Activity Execution concepts and lifecycle.
- Operations: which fields show in describe-like views.
- Permission name DescribeActivityExecution.
- Payloads, converters, and codecs rationale.

What Describe returns by default:
- Activity identity, run status or state, task queue, timeouts, attempt, and timestamps.
- Some surfaces also report the last failure summary and attempt count.

Opt-in payload fields when supported by a surface:
- Input: the arguments provided when the Activity was started.
- Result (outcome): the successful return value.
- Heartbeat details: progress payload recorded by the Activity between retries.
- Last failure: detailed error payload from the most recent failed attempt, if any.

Why inclusion is opt-in:
- Payloads may be large or encoded or encrypted. Include only what you need to avoid heavy responses and to respect data-access constraints.
- If a Payload Codec is configured, raw payload bytes may be opaque without the codec. Prefer summarized fields unless you intend to decode.

Surfaces:
- CLI: temporal activity describe targets Standalone Activities and supports flags such as --activity-id, --run-id, and --raw.
- SDKs: Language clients may expose a describe operation on an Activity handle. Where opt-in payload switches are available, request only the fields you need.

Usage guidance:
- Default to metadata-only describe. Add include flags or options only when the caller explicitly needs the payloads.
- For Heartbeat details, include them for long-running, checkpointed Activities that resume from progress.
- For last failure, include it when triaging or presenting actionable error details to a user.
- Respect codecs and size limits; avoid logging raw payloads.

See language-specific pages for concrete call shapes: references/dotnet/activity-describe-payloads.md, references/go/activity-describe-payloads.md, references/python/activity-describe-payloads.md, references/ruby/activity-describe-payloads.md, references/typescript/activity-describe-payloads.md.
