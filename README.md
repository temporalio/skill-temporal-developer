# Temporal Development Skill

A comprehensive skill for developers to use when building [Temporal](https://temporal.io/) applications.

> [!WARNING]
> This Skill is currently in Public Preview, and will continue to evolve and improve.
> We would love to hear your feedback - positive or negative - over in the [Community Slack](https://t.mp/slack), in the [#topic-ai channel](https://temporalio.slack.com/archives/C0818FQPYKY)

## Installation

### As a Plugin

This skill is packaged as a plugin for major coding agents, which provides a simple way to install and receive future updates:

- **Claude Code**: [temporalio/claude-temporal-plugin](https://github.com/temporalio/claude-temporal-plugin)
- **Cursor**: [temporalio/cursor-temporal-plugin](https://github.com/temporalio/cursor-temporal-plugin)
- **OpenAI Codex**: [temporalio/codex-temporal-plugin](https://github.com/temporalio/codex-temporal-plugin)

See each repo's README for installation instructions.

<details>
<summary><b>Install the Claude Code plugin directly from this repo</b></summary>

This repository ships its own Claude Code marketplace, so you can install the plugin without the separate wrapper repo. From within Claude Code:

1. Add this repo as a marketplace:

   ```
   /plugin marketplace add temporalio/skill-temporal-developer
   ```

2. Install the plugin from it:

   ```
   /plugin install temporal-developer@temporal
   ```

3. Confirm the `temporal-developer` skill is available (e.g. via `/plugin` or by listing skills).

To update later, re-run `/plugin marketplace update temporal` and reinstall.

</details>

### Standalone Installation

If you prefer to install the skill directly without the plugin wrapper:

#### Via `npx skills` — supports all major coding agents

1. `npx skills add temporalio/skill-temporal-developer`
2. Follow prompts

#### Via manually cloning the skill repo

1. `mkdir -p ~/.claude/skills && git clone https://github.com/temporalio/skill-temporal-developer ~/.claude/skills/temporal-developer`

Appropriately adjust the installation directory based on your coding agent.

## Currently Supported Temporal SDK Langages

- [x] Python ✅
- [x] TypeScript ✅
- [x] Go ✅
- [x] Java ✅
- [x] .NET ✅
- [x] Ruby ✅
- [ ] PHP 🚧 ([PR](https://github.com/temporalio/skill-temporal-developer/pull/40))
