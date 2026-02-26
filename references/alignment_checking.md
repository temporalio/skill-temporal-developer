# Alignment Checking

## Purpose

Track content alignment (do files have the right sections?) and style alignment (is prose level appropriate?) across reference files.

**Style target:** Python is the reference style (code-first, minimal prose). TypeScript should match.

**Implementation Status:** ✅ **COMPLETE** (2026-02-25)

All TODO/DEL/BUG items have been implemented. See `.edits.md` files for details of changes made.

---

## Section Inventory

Shows which sections exist in each language. Organized by file.

**Legend:**
- `✓` = present
- ` ` (empty) = missing, unknown if intentional (needs review)
- `—` = missing, intentional (language doesn't need this)
- `TODO` = missing, should add
- `DEL` = present, should remove or merge
- `Py#` / `TS#` = section order in file (should monotonically increase if order is aligned)

### patterns.md

| Section | Core | Python | Py# | TypeScript | TS# | Go |
|---------|------|--------|-----|------------|-----|-----|
| Signals | ✓ | ✓ | 1 | ✓ | 1 | |
| Dynamic Signal Handlers | — | ✓ | 2 | ✓ | 2 | |
| Queries | ✓ | ✓ | 3 | ✓ | 3 | |
| Dynamic Query Handlers | — | ✓ | 4 | ✓ | 4 | |
| Updates | ✓ | ✓ | 5 | ✓ | 5 | |
| Child Workflows | ✓ | ✓ | 6 | ✓ | 6 | |
| Child Workflow Options | — | — | — | ✓ | 7 | |
| Handles to External Workflows | — | ✓ | 7 | ✓ | 8 | |
| Parallel Execution | ✓ | ✓ | 8 | ✓ | 9 | |
| Deterministic Asyncio Alternatives | — | ✓ | 9 | — | — | |
| Continue-as-New | ✓ | ✓ | 10 | ✓ | 10 | |
| Saga Pattern | ✓ | ✓ | 11 | ✓ | 11 | |
| Cancellation Handling (asyncio) | — | ✓ | 12 | — | — | |
| Cancellation Scopes | — | — | — | ✓ | 12 | |
| Triggers | — | — | — | ✓ | 13 | |
| Wait Condition with Timeout | — | ✓ | 13 | ✓ | 14 | |
| Waiting for All Handlers to Finish | — | ✓ | 14 | ✓ | 15 | |
| Activity Heartbeat Details | — | ✓ | 15 | ✓ | 16 | |
| Timers | ✓ | ✓ | 16 | ✓ | 17 | |
| Local Activities | ✓ | ✓ | 17 | ✓ | 18 | |
| Entity Workflow Pattern | ✓ | — | — | — | — | |
| Polling Patterns | ✓ | — | — | — | — | |
| Idempotency Patterns | ✓ | — | — | — | — | |
| Using Pydantic Models | — | ✓ | 18 | — | — | |

### data-handling.md

| Section | Core | Python | Py# | TypeScript | TS# | Go |
|---------|------|--------|-----|------------|-----|-----|
| Overview | — | ✓ | 1 | ✓ | 1 | |
| Default Data Converter | — | ✓ | 2 | ✓ | 2 | |
| Pydantic Integration | — | ✓ | 3 | — | — | |
| Custom Data Converter | — | ✓ | 4 | ✓ | 3 | |
| Payload Encryption | — | ✓ | 5 | ✓ | 4 | |
| Search Attributes | — | ✓ | 6 | ✓ | 5 | |
| Workflow Memo | — | ✓ | 7 | ✓ | 6 | |
| Protobuf Support | — | — | — | ✓ | 7 | |
| Large Payloads | — | ✓ | 8 | ✓ | 8 | |
| Deterministic APIs for Values | — | ✓ | 9 | — | — | |
| Best Practices | — | ✓ | 10 | ✓ | 9 | |

### error-handling.md

| Section | Core | Python | Py# | TypeScript | TS# | Go |
|---------|------|--------|-----|------------|-----|-----|
| Overview | — | ✓ | 1 | ✓ | 1 | |
| Application Errors/Failures | — | ✓ | 2 | ✓ | 2 | |
| Non-Retryable Errors | — | ✓ | 3 | — | — | |
| Activity Errors | — | — | — | ✓ | 3 | |
| Handling Activity Errors in Workflows | — | ✓ | 4 | ✓ | 4 | |
| Retry Configuration | — | ✓ | 5 | ✓ | 5 | |
| Timeout Configuration | — | ✓ | 6 | ✓ | 6 | |
| Workflow Failure | — | ✓ | 7 | ✓ | 7 | |
| Cancellation Handling in Activities | — | — | — | — | — | |
| Idempotency Patterns | — | — | — | — | — | |
| Best Practices | — | ✓ | 8 | ✓ | 9 | |

### gotchas.md

| Section | Core | Core# | Python | Py# | TypeScript | TS# | Go |
|---------|------|-------|--------|-----|------------|-----|-----|
| Idempotency / Non-Idempotent Activities | ✓ | 1 | — | — | — | — | |
| Replay Safety / Side Effects & Non-Determinism | ✓ | 2 | — | — | — | — | |
| Multiple Workers with Different Code | ✓ | 3 | — | — | — | — | |
| Retry Policies / Failing Activities Too Quickly | ✓ | 4 | — | — | — | — | |
| Query Handlers / Query Handler Mistakes | ✓ | 5 | — | — | — | — | |
| File Organization | ✓ | 6 | ✓ | 1 | — | — | |
| Activity Imports | — | — | — | — | ✓ | 1 | |
| Bundling Issues | — | — | — | — | ✓ | 2 | |
| Async vs Sync Activities | — | — | ✓ | 2 | — | — | |
| Error Handling | ✓ | 8 | — | — | — | — | |
| Wrong Retry Classification | ✓ | 8 | ✓ | 3 | ✓ | 3 | |
| Cancellation | — | — | — | — | ✓ | 4 | |
| Heartbeating | — | — | ✓ | 4 | ✓ | 5 | |
| Testing | ✓ | 7 | ✓ | 5 | ✓ | 6 | |
| Timers and Sleep | — | — | ✓ | 6 | ✓ | 7 | |

### observability.md

| Section | Core | Python | Py# | TypeScript | TS# | Go |
|---------|------|--------|-----|------------|-----|-----|
| Overview | — | ✓ | 1 | ✓ | 1 | |
| Logging / Replay-Aware Logging | — | ✓ | 2 | ✓ | 2 | |
| Customizing the Logger | — | ✓ | 2 | ✓ | 3 | |
| OpenTelemetry Integration | — | — | — | — | — | |
| Metrics | — | ✓ | 3 | ✓ | 4 | |
| Search Attributes (Visibility) | — | ✓ | 4 | — | — | |
| Debugging with Event History | — | — | — | — | — | |
| Best Practices | — | ✓ | 5 | ✓ | 5 | |

### testing.md

| Section | Core | Python | Py# | TypeScript | TS# | Go |
|---------|------|--------|-----|------------|-----|-----|
| Overview | — | ✓ | 1 | ✓ | 1 | |
| Test Environment Setup | — | ✓ | 2 | ✓ | 2 | |
| Time Skipping | — | — | — | — | — | |
| Activity Mocking | — | ✓ | 3 | ✓ | 3 | |
| Testing Signals and Queries | — | ✓ | 4 | ✓ | 4 | |
| Testing Failure Cases | — | ✓ | 5 | ✓ | 5 | |
| Replay Testing | — | ✓ | 6 | ✓ | 6 | |
| Activity Testing | — | ✓ | 7 | ✓ | 7 | |
| Best Practices | — | ✓ | 8 | ✓ | 8 | |

### versioning.md

| Section | Core | Core# | Python | Py# | TypeScript | TS# | Go |
|---------|------|-------|--------|-----|------------|-----|-----|
| Overview | ✓ | 1 | ✓ | 1 | ✓ | 1 | |
| Why Versioning is Needed | ✓ | 2 | ✓ | 2 | ✓ | 2 | |
| Patching API | ✓ | 3 | ✓ | 3 | ✓ | 3 | |
| Workflow Type Versioning | ✓ | 4 | ✓ | 4 | ✓ | 4 | |
| Worker Versioning | ✓ | 5 | ✓ | 5 | ✓ | 5 | |
| Choosing a Strategy | ✓ | 6 | ✓ | 6 | ✓ | 6 | |
| Best Practices | ✓ | 7 | ✓ | 6 | ✓ | 7 | |
| Finding Workflows by Version | ✓ | 8 | — | — | — | — | |
| Common Mistakes | ✓ | 9 | — | — | — | — | |

### {language}.md (top-level files)

| Section | Core | Python | Py# | TypeScript | TS# | Go |
|---------|------|--------|-----|------------|-----|-----|
| Overview | — | ✓ | 1 | ✓ | 1 | |
| How Temporal Works: History Replay | — | — | — | — | — | |
| Understanding Replay | — | — | — | ✓ | 2 | |
| Quick Start / Quick Demo | — | ✓ | 2 | ✓ | 3 | |
| Key Concepts | — | ✓ | 3 | ✓ | 4 | |
| File Organization Best Practice | — | ✓ | 4 | ✓ | 5 | |
| Determinism Rules | — | — | — | ✓ | 6 | |
| Common Pitfalls | — | ✓ | 5 | ✓ | 7 | |
| Writing Tests | — | ✓ | 6 | ✓ | 8 | |
| Additional Resources | — | ✓ | 7 | ✓ | 9 | |

### determinism-protection.md

| Section | Core | Python | Py# | TypeScript | TS# | Go |
|---------|------|--------|-----|------------|-----|-----|
| Overview | — | ✓ | 1 | ✓ | 1 | |
| How the Sandbox Works | — | ✓ | 2 | — | — | |
| Import Blocking | — | — | — | ✓ | 2 | |
| Forbidden Operations | — | ✓ | 3 | — | — | |
| Function Replacement | — | — | — | ✓ | 3 | |
| Pass-Through Pattern | — | ✓ | 4 | — | — | |
| Importing Activities | — | ✓ | 5 | — | — | |
| Disabling the Sandbox | — | ✓ | 6 | — | — | |
| Customizing Invalid Module Members | — | ✓ | 7 | — | — | |
| Import Notification Policy | — | ✓ | 8 | — | — | |
| Disable Lazy sys.modules Passthrough | — | ✓ | 9 | — | — | |
| File Organization | — | ✓ | 10 | — | — | |
| Common Issues | — | ✓ | 11 | — | — | |
| Best Practices | — | ✓ | 12 | — | — | |

### determinism.md

| Section | Core | Core# | Python | Py# | TypeScript | TS# | Go |
|---------|------|-------|--------|-----|------------|-----|-----|
| Overview | ✓ | 1 | ✓ | 1 | ✓ | 1 | |
| Why Determinism Matters | ✓ | 2 | ✓ | 2 | ✓ | 2 | |
| Sources of Non-Determinism | ✓ | 3 | — | — | — | — | |
| Central Concept: Activities | ✓ | 4 | — | — | — | — | |
| SDK Protection / Sandbox | ✓ | 5 | ✓ | 6 | ✓ | 3 | |
| Forbidden Operations | — | — | ✓ | 3 | ✓ | 4 | |
| Safe Builtin Alternatives | — | — | ✓ | 4 | — | — | |
| Detecting Non-Determinism | ✓ | 6 | — | — | — | — | |
| Recovery from Non-Determinism | ✓ | 7 | — | — | — | — | |
| Testing Replay Compatibility | — | — | ✓ | 5 | ✓ | 5 | |
| Best Practices | ✓ | 8 | ✓ | 7 | ✓ | 6 | |

---

## Style Alignment: TypeScript vs Python

### patterns.md

#### Signals
- **Python:** Code only
- **TypeScript:** Code only
- **Decision:** all good

---

#### Dynamic Signal Handlers
- **Python:** One-liner intro + code
- **TypeScript:** One-liner intro + code
- **Decision:** all good

---

#### Queries
- **Python:** One-liner note ("must NOT modify state") + code
- **TypeScript:** One-liner note ("must NOT modify state") + code
- **Decision:** ✅ FIXED — TS now has "**Important:** Queries must NOT modify workflow state or have side effects" note

---

#### Dynamic Query Handlers
- **Python:** Code only
- **TypeScript:** One-liner intro + code
- **Decision:** all good

---

#### Updates
- **Python:** Code only (validator shown inline)
- **TypeScript:** Code only (shows both simple and validated handlers)
- **Decision:** all good

---

#### Child Workflows
- **Python:** Code only (shows parent_close_policy inline)
- **TypeScript:** Code only + separate "Child Workflow Options" subsection
- **Decision:** all good (TS has more options to show, subsection is appropriate)

---

#### Handles to External Workflows
- **Python:** Code only
- **TypeScript:** Code only
- **Decision:** all good

---

#### Parallel Execution
- **Python:** Code + "Deterministic Alternatives to asyncio" subsection
- **TypeScript:** Code only (just Promise.all)
- **Decision:** all good (Python needs asyncio alternatives, TS doesn't)

---

#### Continue-as-New
- **Python:** Code only
- **TypeScript:** Code only
- **Decision:** all good

---

#### Saga Pattern
- **Python:** One-liner note ("compensation activities should be idempotent") + code with detailed comments explaining WHY save compensation BEFORE activity
- **TypeScript:** One-liner note + code with detailed comments + replay-safe logging
- **Decision:** ✅ FIXED
  - TS now has "**Important:** Compensation activities should be idempotent" note
  - TS now has comments explaining WHY compensation is saved BEFORE the activity
  - TS now uses `log` from `@temporalio/workflow` for replay-safe logging

---

#### Cancellation Handling (Python) vs Cancellation Scopes (TypeScript)
- **Python:** "Cancellation Handling - leverages standard asyncio cancellation" - code showing asyncio.CancelledError
- **TypeScript:** "Cancellation Scopes" - one-liner + code showing CancellationScope patterns
- **Decision:** all good (different language idioms - Python uses asyncio, TS uses CancellationScope)

---

#### Triggers (TypeScript only)
- **Python:** N/A (no equivalent)
- **TypeScript:** WHY/WHEN + code
- **Decision:** all good (TS-specific pattern, needs explanation)

---

#### Wait Condition with Timeout
- **Python:** Code only
- **TypeScript:** Code only
- **Decision:** all good

---

#### Waiting for All Handlers to Finish
- **Python:** WHY/WHEN (as ### headers) + code
- **TypeScript:** WHY/WHEN (as ### headers) + code
- **Decision:** all good (both have same structure, important pattern worth explaining)

---

#### Activity Heartbeat Details
- **Python:** WHY/WHEN (as ### headers) + code
- **TypeScript:** WHY/WHEN (as ### headers) + code
- **Decision:** all good (both have same structure)

---

#### Timers
- **Python:** Code only (simple sleep example)
- **TypeScript:** Code only (shows sleep + cancellable timer with CancellationScope)
- **Decision:** all good (TS shows more because CancellationScope is TS-specific)

---

#### Local Activities
- **Python:** Purpose note + code
- **TypeScript:** Purpose note + code
- **Decision:** all good (both have same structure, warning is important)

---

### data-handling.md

#### Overview
- **Python:** One-liner describing data converters
- **TypeScript:** One-liner describing data converters
- **Decision:** all good

---

#### Default Data Converter
- **Python:** Bullet list of supported types
- **TypeScript:** Bullet list of supported types
- **Decision:** all good

---

#### Pydantic Integration (Python only)
- **Python:** Explanation + two code blocks (model definition + client setup)
- **TypeScript:** N/A (no equivalent)
- **Decision:** all good (Python-specific feature)

---

#### Custom Data Converter
- **Python:** Brief explanation + links to example files
- **TypeScript:** Brief explanation + full code example
- **Decision:** all good (TS inline example is appropriate; Python linking to samples is also valid)

---

#### Payload Encryption
- **Python:** Code only (with inline comment about GIL)
- **TypeScript:** Code only
- **Decision:** all good

---

#### Search Attributes
- **Python:** Code examples for setting at start, upserting, querying (with typed SearchAttributeKey)
- **TypeScript:** Code examples for setting at start, upserting, reading, querying
- **Decision:** all good (TypeScript has extra "Reading" subsection which is fine)

---

#### Workflow Memo
- **Python:** Code for setting + reading (two separate blocks)
- **TypeScript:** Code for setting + reading (combined block)
- **Decision:** all good

---

#### Protobuf Support (TypeScript only)
- **Python:** N/A
- **TypeScript:** One-liner + code
- **Decision:** all good (TS-specific section)

---

#### Large Payloads
- **Python:** Bullet list + code example (reference pattern)
- **TypeScript:** Bullet list + code example (reference pattern)
- **Decision:** all good

---

#### Deterministic APIs for Values (Python only)
- **Python:** One-liner + code showing workflow.uuid4() and workflow.random()
- **TypeScript:** N/A
- **Decision:** all good (Python-specific; TS doesn't need this section)

---

#### Best Practices
- **Python:** Numbered list (6 items)
- **TypeScript:** Numbered list (6 items)
- **Decision:** all good (content differs slightly but appropriate per language)

---

### error-handling.md

#### Overview
- **Python:** One-liner describing ApplicationError and retry policy; notes applicability to activities, child workflows, Nexus
- **TypeScript:** One-liner describing ApplicationFailure with non-retryable marking
- **Decision:** all good

---

#### Application Errors/Failures
- **Python:** "Application Errors" - code example in activity context
- **TypeScript:** "Application Failures" - code example in workflow context
- **Decision:** all good (different names match SDK terminology)

---

#### Non-Retryable Errors (Python only)
- **Python:** Dedicated section with detailed code example showing non_retryable=True
- **TypeScript:** N/A (covered inline in Application Failures section)
- **Decision:** all good (TS shows nonRetryable inline, Python splits it out for emphasis)

---

#### Activity Errors (TypeScript only)
- **Python:** N/A (covered in Application Errors)
- **TypeScript:** Separate section showing ApplicationFailure in activity context
- **Decision:** all good (TS splits workflow vs activity contexts)

---

#### Handling Activity Errors in Workflows
- **Python:** Code showing try/except with ActivityError, uses `workflow.logger`
- **TypeScript:** Code showing try/catch with ApplicationFailure instanceof check, uses `log`
- **Decision:** ✅ FIXED — TS now uses `log` from `@temporalio/workflow`

---

#### Retry Configuration
- **Python:** Code + note about preferring defaults ("Only set options... if you have a domain-specific reason to")
- **TypeScript:** Code + note about preferring defaults
- **Decision:** ✅ FIXED — TS now has note about preferring defaults

---

#### Timeout Configuration
- **Python:** Code with inline comments explaining each timeout
- **TypeScript:** Code with inline comments explaining each timeout
- **Decision:** all good

---

#### Workflow Failure
- **Python:** Code + note about not using non_retryable in workflows
- **TypeScript:** Code + note about not using nonRetryable in workflows
- **Decision:** ✅ FIXED — TS now has Workflow Failure section

---

#### Cancellation Handling in Activities
- **Python:** N/A
- **TypeScript:** N/A (removed from error-handling.md)
- **Decision:** ✅ DONE — Removed from error-handling.md (patterns.md has Cancellation Scopes)

---

#### Idempotency Patterns (error-handling.md)
- **Python:** N/A (brief mention in Best Practices, references core/patterns.md)
- **TypeScript:** Brief reference to core/patterns.md
- **Decision:** ✅ DONE — Replaced detailed section with brief reference to core

---

#### Best Practices
- **Python:** Numbered list (6 items), includes reference to core/patterns.md for idempotency
- **TypeScript:** Numbered list (7 items), includes idempotency items
- **Decision:** all good

---

### gotchas.md

**Note:** These files have very different structures. TypeScript has 11 detailed sections with code examples. Python has 5 sections and references other docs more heavily.

#### Idempotency
- **Python:** N/A (covered in core/patterns.md)
- **TypeScript:** N/A (removed)
- **Decision:** ✅ DONE — Removed from TypeScript (Core coverage sufficient)

---

#### Replay Safety
- **Python:** N/A
- **TypeScript:** N/A (removed)
- **Decision:** ✅ DONE — Removed from TypeScript (Core coverage sufficient)

---

#### Query Handlers
- **Python:** N/A
- **TypeScript:** N/A (removed)
- **Decision:** ✅ DONE — Removed from TypeScript (Core coverage sufficient)

---

#### File Organization (Python only)
- **Python:** Subsections for Importing Activities and Mixing Workflows/Activities
- **TypeScript:** N/A (covered in Activity Imports section)
- **Decision:** all good (different names, similar concepts)

---

#### Activity Imports (TypeScript only)
- **Python:** N/A (covered in File Organization)
- **TypeScript:** Subsections for type-only imports and Node.js module restrictions
- **Decision:** all good (Python covers import issues in File Organization)

---

#### Bundling Issues (TypeScript only)
- **Python:** N/A
- **TypeScript:** Subsections for Missing Dependencies and Package Version Mismatches
- **Decision:** all good (TS-specific concern due to workflow bundling)

---

#### Async vs Sync Activities (Python only)
- **Python:** Subsections for Blocking in Async and Missing Executor
- **TypeScript:** N/A
- **Decision:** all good (Python-specific concern)

---

#### Error Handling (gotchas.md)
- **Python:** N/A (references error-handling.md)
- **TypeScript:** N/A (removed)
- **Decision:** ✅ DONE — Removed from TypeScript gotchas.md (covered in core and error-handling.md)

---

#### Wrong Retry Classification
- **Python:** Brief note referencing error-handling.md
- **TypeScript:** Brief note + code example + reference to error-handling.md
- **Decision:** ✅ FIXED — Added to TypeScript

---

#### Retry Policies
- **Python:** N/A
- **TypeScript:** N/A (removed)
- **Decision:** ✅ DONE — Removed from TypeScript (Core coverage sufficient)

---

#### Cancellation (TypeScript only)
- **Python:** N/A
- **TypeScript:** "Not Handling Cancellation" with CancellationScope example
- **Decision:** all good (TS-specific due to CancellationScope API)

---

#### Heartbeating
- **Python:** Two subsections: Forgetting to Heartbeat, Timeout Too Short
- **TypeScript:** Two subsections: Forgetting to Heartbeat, Timeout Too Short
- **Decision:** all good (both have equivalent content)

---

#### Testing
- **Python:** Brief note referencing testing.md
- **TypeScript:** Full code examples for failure testing and replay testing
- **Decision:** all good (Python references separate file, TS has inline examples)

---

#### Timers and Sleep
- **Python:** "Using asyncio.sleep" BAD/GOOD example
- **TypeScript:** "Using JavaScript setTimeout" BAD/GOOD example
- **Decision:** ✅ FIXED — Added to Python

---

### observability.md

#### Overview
- **Python:** One-liner mentioning logging, metrics, tracing, visibility
- **TypeScript:** One-liner mentioning replay-aware logging, metrics, OpenTelemetry
- **Decision:** all good

---

#### Logging / Replay-Aware Logging
- **Python:** "Logging" with subsections for Workflow and Activity logging + code examples
- **TypeScript:** "Replay-Aware Logging" with subsections for Workflow and Activity logging + code examples
- **Decision:** all good (different section names, same content structure)

---

#### Customizing the Logger
- **Python:** Subsection under Logging showing basicConfig
- **TypeScript:** Separate section with Basic Configuration + Winston Integration subsections
- **Decision:** all good (TS has more detail for Winston, appropriate)

---

#### OpenTelemetry Integration
- **Python:** N/A
- **TypeScript:** N/A (removed)
- **Decision:** ✅ DONE — Removed from TypeScript (too detailed for reference docs)

---

#### Metrics
- **Python:** Enabling SDK Metrics + Key SDK Metrics subsections
- **TypeScript:** Prometheus Metrics + OTLP Metrics subsections
- **Decision:** all good (both cover metrics, different focus)

---

#### Search Attributes (Python only)
- **Python:** Brief reference to data-handling.md
- **TypeScript:** N/A (covered in data-handling.md)
- **Decision:** all good (Python includes as observability concept, TS keeps in data-handling)

---

#### Debugging with Event History
- **Python:** N/A
- **TypeScript:** N/A (removed)
- **Decision:** ✅ DONE — Removed from TypeScript (too detailed)

---

#### Best Practices
- **Python:** 4 items
- **TypeScript:** 6 items
- **Decision:** all good

---

### testing.md

#### Overview
- **Python:** Multi-sentence describing WorkflowEnvironment and ActivityEnvironment
- **TypeScript:** One-liner mentioning TestWorkflowEnvironment
- **Decision:** all good (Python more detailed intro)

---

#### Test Environment Setup
- **Python:** "Workflow Test Environment" - detailed pattern explanation + code
- **TypeScript:** "Test Environment Setup" - code example with before/after hooks
- **Decision:** all good (both comprehensive)

---

#### Time Skipping
- **Python:** N/A (mentioned inline in environment section)
- **TypeScript:** N/A (mentioned inline in environment section)
- **Decision:** ✅ DONE — Removed dedicated section from TypeScript (now inline like Python)

---

#### Activity Mocking
- **Python:** "Mocking Activities" - code with @activity.defn mock
- **TypeScript:** "Activity Mocking" - inline activity object in Worker.create
- **Decision:** all good

---

#### Testing Signals and Queries
- **Python:** Code example with signal/query
- **TypeScript:** Code example with signal/query
- **Decision:** all good

---

#### Testing Failure Cases
- **Python:** Code example with pytest.raises
- **TypeScript:** Code example with try/catch and WorkflowFailedError
- **Decision:** ✅ FIXED — Added to TypeScript

---

#### Replay Testing
- **Python:** "Workflow Replay Testing" - code with Replayer class
- **TypeScript:** "Replay Testing" - code with Worker.runReplayHistory
- **Decision:** all good

---

#### Activity Testing
- **Python:** Code with ActivityEnvironment
- **TypeScript:** Code with MockActivityEnvironment
- **Decision:** ✅ FIXED — Added to TypeScript

---

#### Best Practices
- **Python:** 6 items
- **TypeScript:** 5 items
- **Decision:** all good

---

### versioning.md

#### Overview
- **Core:** Brief intro listing three approaches
- **Python:** Detailed intro covering all three approaches
- **TypeScript:** Brief intro covering all three approaches
- **Decision:** all good

---

#### Why Versioning is Needed
- **Core:** Conceptual explanation with pseudo-code
- **Python:** Detailed explanation with replay context
- **TypeScript:** "Why Versioning Matters" - similar detailed explanation
- **Decision:** all good

---

#### Patching API
- **Core:** Conceptual with Three-Phase Lifecycle, When to Use, When NOT to Use
- **Python:** Full code examples with patched(), Three-Step Process, Multiple Patches, Query Filters
- **TypeScript:** Full code examples with patched(), Three-Step Process, Multiple Patches, Query Filters
- **Decision:** all good (Core conceptual, languages have implementation details)

---

#### Workflow Type Versioning
- **Core:** Conceptual with process steps
- **Python:** Full code examples with Worker registration
- **TypeScript:** Full code examples with Worker registration
- **Decision:** all good

---

#### Worker Versioning
- **Core:** Key Concepts, PINNED/AUTO_UPGRADE guidance
- **Python:** Full code examples, Deployment Strategies, Querying
- **TypeScript:** Full code examples, Deployment Strategies, Rainbow/Blue-Green
- **Decision:** all good

---

#### Choosing a Strategy
- **Core:** Decision table
- **Python:** Decision table
- **TypeScript:** Decision table
- **Decision:** ✅ FIXED — Added decision table to Python

---

#### Best Practices
- **Core:** 5 items
- **Python:** 7 items
- **TypeScript:** 8 items
- **Decision:** all good

---

#### Finding Workflows by Version (Core only)
- **Core:** CLI examples for querying by version
- **Python:** N/A (covered in Query Filters subsection)
- **TypeScript:** N/A (covered in Query Filters subsection)
- **Decision:** all good (languages include as subsections)

---

#### Common Mistakes (Core only)
- **Core:** 4 common mistakes
- **Python:** N/A
- **TypeScript:** N/A
- **Decision:** — (intentional) — Keep Core-only; conceptual coverage sufficient

---

### {language}.md (top-level files)

#### Overview
- **Python:** One-liner about async/type-safe, Python 3.9+, sandbox
- **TypeScript:** One-liner about async/await, V8 sandbox + version warning
- **Decision:** all good

---

#### How Temporal Works: History Replay
- **Python:** N/A (covered in core/determinism.md)
- **TypeScript:** N/A (removed, replaced with brief "Understanding Replay" section)
- **Decision:** ✅ DONE — Removed from TypeScript; now references core/determinism.md

---

#### Quick Start / Quick Demo
- **Python:** Full multi-file example with activities, workflows, worker, starter
- **TypeScript:** Full multi-file example with activities, workflows, worker, client
- **Decision:** ✅ FIXED — Expanded TypeScript to match Python (see detailed gaps now resolved)

---

#### Key Concepts
- **Python:** Workflow Definition, Activity Definition (sync vs async), Worker Setup, Determinism subsection
- **TypeScript:** Workflow Definition, Activity Definition, Worker Setup (no Determinism subsection)
- **Decision:** all good (TS has separate Determinism Rules section)

---

#### Determinism Rules (TypeScript only)
- **Python:** N/A (has Determinism subsection in Key Concepts)
- **TypeScript:** Separate section with automatic replacements and safe operations
- **Decision:** all good (different organization, both cover determinism)

---

#### File Organization Best Practice
- **Python:** Directory structure + code example for sandbox imports
- **TypeScript:** Directory structure + code example for type-only imports
- **Decision:** ✅ FIXED — Added to TypeScript with bundling/import guidance

---

#### Common Pitfalls
- **Python:** 7 items
- **TypeScript:** 5 items
- **Decision:** all good

---

#### Writing Tests
- **Python:** Reference to testing.md
- **TypeScript:** Reference to testing.md
- **Decision:** all good

---

#### Additional Resources
- **Python:** Correct references to python files
- **TypeScript:** Correct references to typescript files
- **Decision:** ✅ FIXED — Updated TypeScript file paths

---

### determinism-protection.md

**Note:** These files have very different structures due to different sandbox implementations. Python has 12 detailed sections; TypeScript has 3 sections.

#### Overview
- **Python:** One-liner about sandbox protection
- **TypeScript:** One-liner about V8 sandbox
- **Decision:** all good

---

#### How the Sandbox Works (Python only)
- **Python:** Bullet list of sandbox mechanisms
- **TypeScript:** N/A (covered in Overview)
- **Decision:** all good

---

#### Import Blocking (TypeScript only)
- **Python:** N/A
- **TypeScript:** Code example with ignoreModules for bundler
- **Decision:** all good (TS-specific V8 concern)

---

#### Forbidden Operations (Python only)
- **Python:** List of forbidden operations (I/O, threading, subprocess, etc.)
- **TypeScript:** N/A (covered briefly in determinism.md)
- **Decision:** all good

---

#### Function Replacement (TypeScript only)
- **Python:** N/A
- **TypeScript:** Explains Date/Math.random deterministic replacement with code example
- **Decision:** all good (TS-specific V8 feature)

---

#### Pass-Through Pattern (Python only)
- **Python:** Code example with imports_passed_through(), when to use
- **TypeScript:** N/A
- **Decision:** all good (Python-specific sandbox pattern)

---

#### Importing Activities (Python only)
- **Python:** Full code example for activity imports
- **TypeScript:** N/A (uses type-only imports, covered in gotchas.md)
- **Decision:** all good

---

#### Disabling the Sandbox (Python only)
- **Python:** Code with sandbox_unrestricted(), warnings
- **TypeScript:** N/A
- **Decision:** all good (Python-specific escape hatch)

---

#### Customizing Invalid Module Members (Python only)
- **Python:** Detailed code for SandboxRestrictions customization
- **TypeScript:** N/A
- **Decision:** all good (Python-specific advanced config)

---

#### Import Notification Policy (Python only)
- **Python:** Code for warning/error policies
- **TypeScript:** N/A
- **Decision:** all good (Python-specific)

---

#### File Organization (Python only)
- **Python:** Directory structure example
- **TypeScript:** N/A (covered in gotchas.md)
- **Decision:** all good

---

#### Common Issues (Python only)
- **Python:** Import errors and non-determinism from libraries
- **TypeScript:** N/A
- **Decision:** all good

---

#### Best Practices (Python only)
- **Python:** 5 items
- **TypeScript:** N/A (covered in determinism.md)
- **Decision:** all good

---

### determinism.md

#### Overview
- **Core:** One-liner about determinism and replay
- **Python:** One-liner about sandbox protection
- **TypeScript:** One-liner about V8 sandbox
- **Decision:** all good

---

#### Why Determinism Matters
- **Core:** Detailed with Replay Mechanism, Commands/Events table, Non-Determinism Example
- **Python:** "Why Determinism Matters: History Replay" - brief explanation
- **TypeScript:** "Why Determinism Matters" - brief explanation
- **Decision:** all good (Core has conceptual depth, languages are brief)

---

#### Sources of Non-Determinism (Core only)
- **Core:** Detailed categories: Time, Random, External State, Iteration, Threading
- **Python:** N/A (covered in Forbidden Operations)
- **TypeScript:** N/A (covered in Forbidden Operations)
- **Decision:** all good (Core conceptual, languages list forbidden operations)

---

#### Central Concept: Activities (Core only)
- **Core:** Explains activities as primary mechanism for non-deterministic code
- **Python:** N/A
- **TypeScript:** N/A
- **Decision:** all good (important conceptual point in Core)

---

#### SDK Protection / Sandbox
- **Core:** Brief mention of both Python and TypeScript sandboxes
- **Python:** "Sandbox Behavior" - describes isolation mechanisms
- **TypeScript:** "Temporal's V8 Sandbox" - code example + explanation
- **Decision:** all good

---

#### Forbidden Operations
- **Core:** N/A (covered in Sources)
- **Python:** Bullet list of forbidden operations
- **TypeScript:** Code example of forbidden imports/operations
- **Decision:** all good

---

#### Safe Builtin Alternatives (Python only)
- **Core:** N/A
- **Python:** Table mapping forbidden → safe alternatives
- **TypeScript:** N/A
- **Decision:** — (intentional) — Keep as Python-only; TS V8 sandbox handles this automatically

---

#### Detecting Non-Determinism (Core only)
- **Core:** During Execution + Testing with Replay subsections
- **Python:** N/A
- **TypeScript:** N/A
- **Decision:** all good (conceptual content in Core)

---

#### Recovery from Non-Determinism (Core only)
- **Core:** Accidental Change + Intentional Change subsections
- **Python:** N/A
- **TypeScript:** N/A
- **Decision:** all good (conceptual content in Core)

---

#### Testing Replay Compatibility
- **Core:** N/A (covered in Detecting subsection)
- **Python:** Reference to testing.md
- **TypeScript:** Reference to testing.md
- **Decision:** all good

---

#### Best Practices
- **Core:** 5 items
- **Python:** 7 items
- **TypeScript:** 5 items
- **Decision:** all good

---

## Summary

### patterns.md

**Sections needing review (empty cells):**
- Go column: all empty — Go files not yet created

**Decided to keep as Core-only:**
- Polling Patterns: Core conceptual explanation sufficient
- Idempotency Patterns: Core conceptual explanation sufficient

**Intentionally missing (`—`):**
- Dynamic handlers, External workflow handles, Wait conditions, Heartbeat details: language-specific implementation, core has concepts only
- Child Workflow Options: TS-specific (Python shows inline)
- Deterministic Asyncio Alternatives: Python-specific (TS doesn't have this issue)
- Cancellation Handling vs Cancellation Scopes: different idioms per language
- Triggers: TS-specific pattern
- Entity Workflow Pattern: conceptual in core, implementation left to user
- Using Pydantic Models: Python-specific

**Order alignment:** ✓ Aligned — TS# monotonically increases

**Style alignment:** ✅ All issues fixed
- ✅ **Queries:** TS now has "Important: must NOT modify state" note
- ✅ **Saga Pattern:** TS now has idempotency note, comments about saving compensation BEFORE activity
- ✅ **Saga Pattern:** TS now uses `log` from `@temporalio/workflow`

### data-handling.md

**Sections needing review (empty cells):**
- Go column: all empty — Go files not yet created

**Intentionally missing (`—`):**
- Core column: data handling is implementation-specific, no core concepts doc needed
- Pydantic Integration: Python-specific (TS uses plain JSON/types)
- Protobuf Support: TS-specific section (Python handles protobufs via default converter)
- Deterministic APIs for Values: Python-specific (`workflow.uuid4()`, `workflow.random()`)

**Order alignment:** ✅ ALIGNED — Reordered TypeScript to match Python order

**Style alignment:** All TypeScript sections aligned with Python. No changes needed.

### error-handling.md

**Sections needing review (empty cells):**
- Go column: all empty — Go files not yet created

**Intentionally missing (`—`):**
- Core column: error handling is implementation-specific, no core concepts doc needed
- Non-Retryable Errors: TS covers inline in Application Failures
- Activity Errors: Python covers in Application Errors
- Workflow Failure: TS-specific section not needed (different SDK design)
- Idempotency Patterns: TS-specific detailed section; Python references core/patterns.md

**Sections marked DEL:**
- Cancellation Handling in Activities: Move from error-handling.md to patterns.md

**Order alignment:** ✓ Aligned — TS# monotonically increases

**Action items:** ✅ All completed
- ✅ **TypeScript:** Added Workflow Failure section with nonRetryable warning
- ✅ **TypeScript:** Removed Cancellation Handling in Activities section
- ✅ **TypeScript:** Replaced Idempotency Patterns with brief reference to core

**Style alignment:** ✅ All issues fixed
- ✅ **Handling Activity Errors:** TS now uses `log` from `@temporalio/workflow`
- ✅ **Retry Configuration:** TS now has note about preferring defaults

### gotchas.md

**Sections needing review (empty cells):**
- Go column: all empty — Go files not yet created

**Decided to keep as-is:**
- Multiple Workers with Different Code: Core-only (conceptual explanation sufficient)
- Heartbeating: Py/TS-only (language-specific code examples, no Core conceptual section needed)

**Intentionally missing (`—`):**
- Idempotency, Replay Safety, Query Handlers, Error Handling, Retry Policies: Core-only (conceptual)
- Multiple Workers with Different Code: Core-only (conceptual)
- File Organization: Core + Python; TS covers similar in Activity Imports
- Activity Imports: TS-specific (bundling/sandbox concerns)
- Bundling Issues: TS-specific (workflow bundling)
- Async vs Sync Activities: Python-specific
- Cancellation: TS-specific (CancellationScope API)
- Timers and Sleep: TS-specific

**Order alignment:** N/A after cleanup — Core has conceptual sections, language files have implementation-specific sections

**Action items:** ✅ All completed
- ✅ **TypeScript DEL:** Removed Idempotency, Replay Safety, Retry Policies, Query Handlers, Error Handling
- ✅ **TypeScript:** Added Wrong Retry Classification section
- ✅ **Python:** Added Timers and Sleep section

**Style alignment:** ✅ Complete:
- Core: 8 conceptual sections with symptoms/fixes (authoritative for cross-cutting concerns)
- TypeScript: 7 sections (Activity Imports, Bundling, Cancellation, Heartbeating, Testing, Timers, Wrong Retry Classification)
- Python: 5 sections (File Organization, Async vs Sync, Wrong Retry Classification, Heartbeating, Testing)

### observability.md

**Sections needing review (empty cells):**
- Go column: all empty — Go files not yet created

**Intentionally missing (`—`):**
- Core column: no core observability.md exists (implementation-specific)
- Search Attributes: Python includes as observability concept; TS keeps in data-handling.md

**Sections marked DEL:**
- OpenTelemetry Integration: Remove from TypeScript (too detailed)
- Debugging with Event History: Remove from TypeScript (too detailed)

**Order alignment:** ✓ Aligned — TS# monotonically increases (Py# 2 maps to both TS# 2 and 3, but order preserved)

**Action items:** ✅ All completed
- ✅ DEL: Removed OpenTelemetry Integration from TypeScript
- ✅ DEL: Removed Debugging with Event History from TypeScript

**Style alignment:** ✅ Complete. TS is now concise like Python.

### testing.md

**Sections needing review (empty cells):**
- Go column: all empty — Go files not yet created

**Intentionally missing (`—`):**
- Core column: no core testing.md exists (implementation-specific)
- Testing Failure Cases: Python-specific section (adding to TS)
- Activity Testing: Python-specific (ActivityEnvironment) (adding to TS)

**Sections marked DEL:**
- Time Skipping: Remove dedicated section from TypeScript (mention inline like Python)

**Order alignment:** ✅ ALIGNED — Reordered TS sections to match Python order

**Action items:** ✅ All completed
- ✅ Added Testing Failure Cases section to TypeScript
- ✅ Added Activity Testing section to TypeScript
- ✅ Reordered TS sections (Signals/Queries before Replay)

**Style alignment:** ✅ Complete. Python and TypeScript now have matching sections.

### versioning.md

**Sections needing review (empty cells):**
- Go column: all empty — Go files not yet created

**Intentionally missing (`—`):**
- Choosing a Strategy: Python missing (TS + Core have decision table)
- Finding Workflows by Version: Core-only section (languages cover in Query Filters subsections)
- Common Mistakes: Core-only section

**Order alignment:** ✓ Aligned — all three files follow same order (Overview, Why, Patching, Type Versioning, Worker Versioning, Best Practices)

**Action items:** ✅ All completed
- ✅ Added Choosing a Strategy decision table to Python versioning.md

**Decided to keep as-is:**
- Common Mistakes: Core-only (conceptual coverage sufficient)

**Style alignment:** ✓ Well aligned
- Core: Conceptual explanations with decision guidance
- Python/TypeScript: Full code examples matching Core structure
- All three cover the same three approaches consistently

### {language}.md (top-level files)

**Sections needing review (empty cells):**
- Go column: all empty — Go files not yet created

**Intentionally missing (`—`):**
- Core column: no core top-level file (these are language entry points)
- Determinism Rules — TS has separate section; Python has subsection in Key Concepts

**Sections marked DEL:**
- How Temporal Works: History Replay — Remove from TS (reference core/determinism.md instead)

**Sections marked TODO:**
- File Organization Best Practice — Add to TypeScript

**Order alignment:** ⚠️ NOT ALIGNED — different structures
- TS has "How Temporal Works" section that Python doesn't have
- TS has separate "Determinism Rules" section; Python has it as Key Concepts subsection
- Python has "File Organization" section that TS doesn't have

**Action items:** ✅ All completed
- ✅ **FIX BUG:** Fixed TypeScript Additional Resources paths
- ✅ **TypeScript DEL:** Removed "How Temporal Works: History Replay" section (now brief "Understanding Replay")
- ✅ **TypeScript:** Added "File Organization Best Practice" section

**TypeScript Quick Start gaps:** ✅ All fixed
- ✅ Added "Add Dependency" instruction
- ✅ Added File descriptions explaining purpose
- ✅ Added "Start the dev server" instruction
- ✅ Added "Start the worker" instruction
- ✅ Added client.ts file showing how to execute a workflow
- ✅ Added "Run the workflow" instruction with expected output

**TypeScript Key Concepts gaps:** ✅ Fixed
- ✅ Added `heartbeat()` mention for long operations

**TypeScript Common Pitfalls gaps:** ✅ All fixed
- ✅ Added "Forgetting to heartbeat" pitfall
- ✅ Added "Using console.log in workflows" pitfall

**Style alignment:** ✅ Complete
- Python Quick Demo and TypeScript Quick Start now match (full tutorial with 4 files, run instructions, expected output)
- Python and TypeScript Key Concepts now aligned
- Python and TypeScript Common Pitfalls now aligned

### determinism-protection.md

**Sections needing review (empty cells):**
- Go column: all empty — Go files not yet created

**Intentionally missing (`—`):**
- Core column: no core file (sandbox implementation is language-specific)
- Most sections are language-specific due to different sandbox architectures:
  - Python: Pass-through pattern, customization APIs, notification policies
  - TypeScript: Import blocking, function replacement (V8-specific)

**Order alignment:** N/A — files have completely different structures (Python: 12 sections, TS: 3 sections)

**Action items:**
- None — different sandboxes require different documentation

**Style alignment:** ⚠️ Very different structures (intentional)
- Python: Comprehensive (12 sections) — complex sandbox with many customization options
- TypeScript: Minimal (3 sections) — V8 sandbox is mostly automatic
- This is appropriate given the different sandbox architectures

### determinism.md

**Sections needing review (empty cells):**
- Go column: all empty — Go files not yet created

**Intentionally missing (`—`):**
- Sources of Non-Determinism: Core-only (conceptual categories)
- Central Concept: Activities: Core-only (conceptual)
- Forbidden Operations: Language-specific (Core covers in Sources)
- Safe Builtin Alternatives: Python-only (table format)
- Detecting Non-Determinism: Core-only
- Recovery from Non-Determinism: Core-only
- Testing Replay Compatibility: Language-specific (Core covers in Detecting)

**Order alignment:** ⚠️ NOT ALIGNED — different structures
- Core#5 (SDK Protection) → Py#6, TS#3
- Languages have Forbidden Operations (Py#3, TS#4) which Core doesn't have as separate section
- Each file follows own logical structure

**Action items:**
- None — Safe Builtin Alternatives intentionally Python-only (TS V8 sandbox handles automatically)

**Style alignment:** ✓ Well aligned
- Core: Deep conceptual content (replay mechanism, commands/events, recovery)
- Python: Practical focus (forbidden operations, safe alternatives table, sandbox)
- TypeScript: Practical focus (V8 sandbox, forbidden operations)
- Good division: Core explains "why", languages explain "how"

### advanced-features.md

| Section | Core | Python | Py# | TypeScript | TS# | Go |
|---------|------|--------|-----|------------|-----|-----|
| Schedules | — | ✓ | 1 | ✓ | 1 | |
| Async Activity Completion | — | ✓ | 2 | ✓ | 2 | |
| Sandbox Customization | — | ✓ | 3 | — | — | |
| Gevent Compatibility Warning | — | ✓ | 4 | — | — | |
| Worker Tuning | — | ✓ | 5 | ✓ | 3 | |
| Workflow Init Decorator | — | ✓ | 6 | — | — | |
| Workflow Failure Exception Types | — | ✓ | 7 | — | — | |
| Continue-as-New | — | — | — | — | — | |
| Workflow Updates | — | — | — | — | — | |
| Nexus Operations | — | — | — | — | — | |
| Activity Cancellation and Heartbeating | — | — | — | — | — | |
| Sinks | — | — | — | ✓ | 4 | |
| CancellationScope Patterns | — | — | — | — | — | |
| Best Practices | — | — | — | — | — | |

---

## Style Alignment: advanced-features.md

#### Schedules
- **Python:** Code example with create_schedule, manage schedules
- **TypeScript:** Code example with schedule.create, manage schedules
- **Decision:** all good

---

#### Async Activity Completion
- **Python:** Detailed section with task_token pattern, external completion code
- **TypeScript:** Detailed section with task_token pattern, external completion code
- **Decision:** ✅ FIXED — Added to TypeScript

---

#### Sandbox Customization (Python only)
- **Python:** Brief reference to determinism-protection.md
- **TypeScript:** N/A (has determinism-protection.md directly)
- **Decision:** all good (Python provides helpful cross-reference)

---

#### Gevent Compatibility Warning (Python only)
- **Python:** Warning about gevent incompatibility with workarounds
- **TypeScript:** N/A
- **Decision:** all good (Python-specific concern)

---

#### Worker Tuning
- **Python:** Code example with max_concurrent_*, activity_executor, graceful_shutdown_timeout
- **TypeScript:** Code example with max_concurrent_*, shutdown timeout, cache settings
- **Decision:** ✅ FIXED — Added to TypeScript

---

#### Workflow Init Decorator (Python only)
- **Python:** Code example with @workflow.init
- **TypeScript:** N/A
- **Decision:** all good (Python-specific feature)

---

#### Workflow Failure Exception Types (Python only)
- **Python:** Code examples for per-workflow and worker-level configuration
- **TypeScript:** N/A
- **Decision:** all good (Python-specific configuration)

---

#### Continue-as-New
- **Python:** N/A (in patterns.md)
- **TypeScript:** N/A (removed, covered in patterns.md)
- **Decision:** ✅ DONE — Removed from advanced-features.md (already in patterns.md)

---

#### Workflow Updates
- **Python:** N/A (in patterns.md)
- **TypeScript:** N/A (removed, covered in patterns.md)
- **Decision:** ✅ DONE — Removed from advanced-features.md (already in patterns.md)

---

#### Nexus Operations
- **Python:** N/A
- **TypeScript:** N/A (removed)
- **Decision:** ✅ DONE — Removed from TypeScript (too advanced for reference docs)

---

#### Activity Cancellation and Heartbeating
- **Python:** N/A (Heartbeat Details in patterns.md)
- **TypeScript:** N/A (removed)
- **Decision:** ✅ DONE — Removed from TypeScript (Heartbeat Details already in patterns.md)

---

#### Sinks (TypeScript only)
- **Python:** N/A
- **TypeScript:** Full example with proxySinks, worker implementation
- **Decision:** all good (TS-specific feature for workflow logging)

---

#### CancellationScope Patterns
- **Python:** N/A (has Cancellation Handling in patterns.md)
- **TypeScript:** N/A (removed, covered in patterns.md)
- **Decision:** ✅ DONE — Removed from advanced-features.md (already in patterns.md)

---

#### Best Practices (advanced-features.md)
- **Python:** N/A
- **TypeScript:** N/A (removed)
- **Decision:** ✅ DONE — Removed from TypeScript (best practices covered in individual sections)

---

## Summary: advanced-features.md

**Sections marked TODO:**
- Async Activity Completion: Add to TypeScript
- Worker Tuning: Add to TypeScript

**Sections needing review (empty cells):**
- Go column: all empty — Go files not yet created

**Intentionally missing (`—`):**
- Core column: advanced features are implementation-specific
- Sandbox Customization: TS has determinism-protection.md directly
- Gevent Compatibility Warning: Python-specific
- Workflow Init Decorator: Python-specific (@workflow.init)
- Workflow Failure Exception Types: Python-specific
- Continue-as-New, Workflow Updates: Python has in patterns.md (appropriate location)
- Nexus Operations: Removed (too advanced)
- Sinks: TS-specific feature

**Sections marked DEL (duplicates/remove in TypeScript):**
- Continue-as-New: Already in patterns.md TS#10
- Workflow Updates: Already in patterns.md TS#5
- Nexus Operations: Too advanced for reference docs
- CancellationScope Patterns: Already in patterns.md TS#12 as "Cancellation Scopes"
- Activity Cancellation and Heartbeating: Heartbeat Details already in patterns.md; ActivityCancellationType not needed
- Best Practices: Remove (covered in individual sections)

**Order alignment:** N/A — files have very different structures; TS has many duplicates that should be removed

**Action items:** ✅ All completed
1. ✅ **TypeScript DEL:** Removed Continue-as-New, Workflow Updates, CancellationScope Patterns
2. ✅ **TypeScript DEL:** Removed Nexus Operations
3. ✅ **TypeScript DEL:** Removed Activity Cancellation and Heartbeating
4. ✅ **TypeScript DEL:** Removed Best Practices
5. ✅ **TypeScript:** Added Async Activity Completion
6. ✅ **TypeScript:** Added Worker Tuning

**Style alignment:** ✅ Complete:
- Python: 7 sections (Schedules, Async Activity Completion, Sandbox Customization, Gevent Warning, Worker Tuning, Workflow Init, Failure Exception Types)
- TypeScript: 4 sections (Schedules, Async Activity Completion, Worker Tuning, Sinks)
- Both serve as "miscellaneous advanced topics" not covered elsewhere

---

### Other files

Not yet inventoried. Add sections as files are reviewed.
