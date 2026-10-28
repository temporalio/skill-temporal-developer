# Payload Validation Errors (Cross-SDK)

Use a non-retryable Application Failure to fail fast on permanently invalid input (for example, schema or business-rule validation). This avoids waiting for retries that cannot succeed.

- Non-retryable errors are created per SDK and will not retry regardless of the Retry Policy.
- In TypeScript, set nonRetryable: true on ApplicationFailure.create({...}). The example also shows details: [...] for structured context.
- In Python, raise ApplicationError(..., non_retryable=True).

## When to use

- Invalid or missing fields that cannot be corrected by retrying the same Activity/Workflow input.
- Business-rule violations (for example, disallowed state transitions).

Avoid overusing non-retryable errors; prefer Retry Policies for transient failures.

## Failure Converter and details

- By default, the Failure Converter copies error message and stack as plain text. You can opt-in to encoding these common attributes.
- TypeScript’s details array on ApplicationFailure.create can carry structured context that passes through your Data Converter/Codecs. Cite details only where documented.

## Language-specific pages

- Python: references/python/payload-validation-errors.md
- TypeScript: references/typescript/payload-validation-errors.md
