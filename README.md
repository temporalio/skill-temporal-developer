# Temporal Development Skill

A comprehensive skill for building Temporal applications.

## Installation

### As a Claude Code Plugin

1. Run `/plugin marketplace add temporalio/agent-skills#dev` 
2. Run `/plugin` to open the plugin manager
3. Select **Marketplaces**
4. Choose `temporal-marketplace` from the list
5. Select **Enable auto-update** or **Disable auto-update**
6. run `/plugin install temporal-developer@temporalio-agent-skills` 
7. Restart Claude Code

### Via `npx skills` - supports all major coding agents

1. `npx skills add https://github.com/temporalio/skill-temporal-developer/tree/dev`
2. Follow prompts

### Via manually cloning the skill repo:

1. `mkdir -p ~/.claude/skills && git clone https://github.com/temporalio/skill-temporal-developer ~/.claude/skills/temporal-developer`

Appropriately adjust the installation directory based on your coding agent.
