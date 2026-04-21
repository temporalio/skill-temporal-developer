# AI Patterns Compatibility Note

The earlier Temporal-derived repository contained AI-oriented orchestration guidance.

This Cadence skill now stays within official Cadence scope and does not provide a separate Cadence-specific AI patterns reference.

Use the normal Cadence workflow building blocks instead:

- activities for model and tool calls
- signals for external input
- queries for inspection
- child workflows for decomposition
- continue-as-new for long-running orchestration

If you need a feature comparison against the old Temporal-derived content, see `references/non-compatible/README.md`.
