# Activity Describe Payloads (Ruby)

Ruby exposes ActivityHandle and its describe operation for Standalone Activities.
- Get a handle: Temporalio::Client#activity_handle.
- Describe: handle.describe returns metadata including status, timestamps, attempt, and last failure.

Opt-in payload inclusion:
- Include input, result, heartbeat details, and last failure payloads only when the caller needs them.

CLI fallback for describe: temporal activity describe with --activity-id and optional --run-id.
