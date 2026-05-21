# How to install Temporal CLI

<!-- Source: docs/cli/setup-cli.mdx (Install the CLI) -->

## macOS

Homebrew or CDN tarball:

```bash
brew install temporal
```

- [Darwin amd64](https://temporal.download/cli/archive/latest?platform=darwin&arch=amd64)
- [Darwin arm64](https://temporal.download/cli/archive/latest?platform=darwin&arch=arm64)

Extract any downloaded archive and add the `temporal` binary to your `PATH`. <!-- docs/cli/setup-cli.mdx:46 -->

## Linux

Homebrew (if available), Snap, or CDN tarball: <!-- docs/cli/setup-cli.mdx:55-60 -->

```bash
brew install temporal
# or
snap install temporal
```

- [Linux amd64](https://temporal.download/cli/archive/latest?platform=linux&arch=amd64)
- [Linux arm64](https://temporal.download/cli/archive/latest?platform=linux&arch=arm64)

Extract any downloaded archive and add the `temporal` binary to your `PATH`.

## Windows

Download from the CDN: <!-- docs/cli/setup-cli.mdx:76-78 -->

- [Windows amd64](https://temporal.download/cli/archive/latest?platform=windows&arch=amd64)
- [Windows arm64](https://temporal.download/cli/archive/latest?platform=windows&arch=arm64)

Extract the archive and add the `temporal.exe` binary to your `PATH`.

## Docker

```bash
docker run --rm temporalio/temporal --help
```

<!-- docs/cli/setup-cli.mdx:87-89 -->

## `tcld` (Temporal Cloud CLI)

Needed for Cloud-connected development (managing Cloud namespaces, API keys, etc.).

Homebrew:

```bash
brew install temporalio/brew/tcld
```

<!-- Source: skill-temporal-cli SKILL.md install section -->