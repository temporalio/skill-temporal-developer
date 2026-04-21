# Cadence Go Data Handling

## Workflow Inputs

Keep workflow and activity inputs serializable and stable across deployments.

Prefer explicit structs over loose maps for long-lived data.

## Memo And Search Attributes

Use `StartWorkflowOptions`:

- `Memo` for non-indexed metadata
- `SearchAttributes` for indexed metadata

Search attributes require advanced visibility support and allowlisted keys.

## Search Attribute Updates

Use `workflow.UpsertSearchAttributes` from workflow code when supported by your server and deployment.

## Compatibility Guidance

Be careful changing serialized field names or meanings for workflows that may replay old histories.
