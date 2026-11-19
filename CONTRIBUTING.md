# Contributing

## Development setup

Manually clone the skill repository following the instructions in the [project README](README.md), then install the development tools and their pinned dependencies:

```shell
uv sync
```

## Validation

Validate the skill metadata and structure:

```shell
uv run --frozen skills-ref validate "$PWD"
```

Check formatting without changing files:

```shell
uv run --frozen rumdl fmt --check .
```

Format all Markdown files:

```shell
uv run rumdl fmt .
```

Check relative Markdown links and heading anchors:

```shell
uv run --frozen rumdl check .
```
