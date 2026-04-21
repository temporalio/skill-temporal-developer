# Cadence Go Gotchas

## Native `go`, `chan`, `select`

Never use them in workflow code. Use workflow equivalents.

## Map Iteration

Sort keys before iterating if output affects workflow decisions.

## Activity Registration

Ensure the worker registers the workflow and all activities actually used by the task list.

## Query Handlers

Queries must not mutate state or block.

## Search Attributes

They require cluster support and allowlisting.
