# t4-ai-setup

A working user-level setup for **Claude Code** and the **GitHub Copilot CLI** —
global instructions, settings, hooks, a statusline, skills, and the command-line
tools those settings depend on — installed by one command.

No credentials, chat history or project memories are included. You log in with
your own account.

## Platform support

| Platform | Claude Code | Copilot CLI |
| --- | --- | --- |
| Windows 11 | ✅ | ✅ |
| WSL | ✅ — [detail](claude/wsl/README.md) | ⏳ planned — [notes](copilot/wsl/README.md) |
| macOS | ⏳ planned — [notes](claude/macos/README.md) | ⏳ planned — [notes](copilot/macos/README.md) |

## Install

One command per tool — run whichever you want, or both.

**Claude Code — Windows** (PowerShell):

```powershell
irm https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-windows.ps1 | iex
```

**Claude Code — WSL** (bash, inside the distro):

```bash
curl -fsSL https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-wsl.sh | bash
```

**Copilot CLI — Windows** (PowerShell):

```powershell
irm https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-copilot-windows.ps1 | iex
```

All are idempotent — safe to re-run, and anything already installed is skipped.

### Prerequisites

**Windows:**

- Windows 11 with `winget` available.
- For Claude Code: the `claude` CLI already installed and logged in — the
  installer configures it but does not install it. (The Copilot installer does
  install the `copilot` CLI if it's missing; you still log in yourself.)
- **An elevated PowerShell if Node.js is not yet installed** — the official
  Node.js MSI cannot self-elevate. If you already have `node`, a normal prompt
  is fine.

**WSL:**

- `sudo` rights, plus `curl` and `tar`.
- **`python3` is required, not optional** — it renders `settings.json` and both
  hooks run under it. The installer stops early if it is missing.
- The `claude` CLI already installed and logged in.

### Passing flags

On Windows, `| iex` cannot pass arguments, so build a scriptblock instead:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-windows.ps1))) -SkipToolchain -SkipPlugins
```

On WSL, flags pass straight through after `-s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-wsl.sh | bash -s -- --skip-toolchain --skip-plugins
```

The full installer flag list is in [`claude/README.md`](claude/README.md),
[`claude/wsl/README.md`](claude/wsl/README.md) and
[`copilot/README.md`](copilot/README.md). The bootstrap itself takes one flag of
its own — `-Ref` on Windows, `--ref` on WSL — see
[Pinning to a fixed version](#pinning-to-a-fixed-version).

## What each installer does

- **Claude Code** — writes 16 files into `~/.claude` (instructions, settings,
  two Python hooks, a statusline, the graphify skill) and installs the tools
  those settings need. Detail: [`claude/README.md`](claude/README.md) for
  Windows, [`claude/wsl/README.md`](claude/wsl/README.md) for WSL.
- **Copilot CLI** — writes 11 files into `~/.copilot` (instructions, settings,
  LSP config, five Python hooks, hook registrations) and the same toolchain.
  Detail: [`copilot/README.md`](copilot/README.md).

Neither installer upgrades a tool you already have; version policy only applies
when a command is missing. Both git-commit your existing `~/.claude` /
`~/.copilot` into a local repo before writing anything, so there is an undo
path.

## This runs remote code

It is a script from the internet piped into your shell. Read it first — `irm`
on its own prints it without running it:

```powershell
irm https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-windows.ps1
```

### Pinning to a fixed version

Two things carry a version, and **both** have to be pinned:

1. the URL you fetch the bootstrap from, and
2. `-Ref`, which decides the version of the repo the bootstrap downloads.

Pinning only the URL does **not** pin the install — the bootstrap still defaults
to `-Ref main` and would fetch the latest config. Pin both, to the same ref:

```powershell
$ref = "v1.0.0"   # a tag, branch or commit SHA
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/toperux/t4-ai-setup/$ref/install-claude-windows.ps1"))) -Ref $ref
```

Add any installer flags after `-Ref $ref`.

Two settings are opinionated and worth reviewing before your first run —
`permissions.defaultMode: "auto"` and `skipDangerousModePermissionPrompt: true`.
See the per-tool READMEs.

## Repository layout

```
.gitattributes                 `* -text` — config files ship byte for byte
.gitignore
install-claude-windows.ps1     entry point, downloads this repo and runs the installer
install-claude-wsl.sh
install-copilot-windows.ps1
claude/
  shared/                      config that is the same on every platform
  windows/
    setup-claude-windows.ps1   the installer
    config/                    the Windows-only config
  wsl/
    setup-claude-wsl.sh
    config/                    the WSL-only config
  macos/                       placeholder
copilot/                       same shape, Windows only so far
```

The Windows bootstrap downloads a zip; the WSL one downloads a tarball, because
`tar` is on every distro while `unzip` often isn't — and unlike the zip, the
tarball preserves the executable bit.

Config is split into a platform-neutral `shared/` tree and a per-platform
overlay, and the installer merges the two with the overlay winning. That keeps
the portable ~85% of the config in one place rather than triplicated once WSL
and macOS land.

The one file that is neither fully portable nor fully platform-specific — the
global instructions — is **composed at install time** from
`shared/CLAUDE.core.md` plus `windows/config/CLAUDE.append.md`. The two halves
are a byte cut of the original file, joined byte for byte, so what lands in
`~/.claude/CLAUDE.md` is exactly the original.

## License

[MIT](LICENSE).
