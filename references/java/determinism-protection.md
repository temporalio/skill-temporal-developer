# Cadence Java Determinism Protection

Cadence Java protects replay correctness by running workflow code through the workflow runtime, but developers still need to keep workflow code disciplined.

Practical rules:

1. Keep workflow logic separate from activity implementations.
2. Use `Workflow.getVersion` before changing workflow structure.
3. Keep workflow state explicit in fields on the workflow implementation.
4. Add unit tests around timers, signals, and replay-sensitive branches.
