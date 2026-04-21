# Cadence Go Determinism Protection

Cadence Go relies mostly on coding discipline and test coverage rather than a workflow sandbox.

Practical protections:

1. Keep workflow code separate from activity code.
2. Use workflow APIs for time, concurrency, and waiting.
3. Add replay-sensitive unit tests for signal, timer, and branching logic.
4. Use `GetVersion` before changing workflow command structure.
