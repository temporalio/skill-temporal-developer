# Cadence Java Data Handling

## Workflow Arguments

Use stable, serializable value objects for workflow and activity inputs.

## Memo And Search Attributes

Use `WorkflowOptions.Builder` to attach:

- memo for non-indexed metadata
- search attributes for indexed metadata

Search attributes require Cadence visibility support and allowlisting.

## Compatibility Guidance

Changing serialized field meaning for long-lived workflows can break application behavior even when replay stays technically valid. Prefer additive schema evolution.
