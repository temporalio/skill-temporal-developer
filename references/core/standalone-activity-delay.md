# Standalone Activity Start Delay

See core docs.

Standalone Activities support a Start Delay to defer dispatch of the first Activity Task after creation. Use it to run jobs later (for example, reminder emails or deferred cleanups) without creating a Schedule.

## Start with the CLI

Start a Standalone Activity to run later:

 delays dispatch of the first Activity Task and does not apply to retry attempts.

### Change the delay before first dispatch

Before the first Activity Task has been dispatched, you can change the delay on a Standalone Activity:

For a Standalone Activity before its first dispatch,  changes when the first task becomes available; duration is measured from the original schedule time.  makes it available immediately. It cannot be changed after the first task dispatch and is not supported for workflow Activities.

### Pause/Unpause semantics

Unpausing before the first attempt honors the original Start Delay deadline; if it has already passed, the Activity dispatches immediately. The delay does not restart and does not apply to retries.

## Visibility: find delayed jobs

Use a List Filter to find Standalone Activities with a Start Delay in the future (job created but first task not yet dispatched):

This query targets delayed jobs by checking  and .

## Common mistakes

## Related references

