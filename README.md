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
| WSL | ✅ — [detail](claude/wsl/README.md) | ✅ — [detail](copilot/wsl/README.md) |
| macOS | ✅ — [detail](claude/macos/README.md) (tested on Apple Silicon) | ✅ — [detail](copilot/macos/README.md) (cask install untested) |

## Before you run it

This replaces your **user-level** config for the tool you install, and one
Claude setting is deliberately permissive — worth a conscious decision rather
than a surprise, especially if you are rolling this out to other people:

- `permissions.defaultMode: "auto"` — tool calls auto-approve instead of
  prompting. Claude Code's own dangerous-mode warning is left in place. Copilot
  has no equivalent setting.

A deny list and a PreToolUse hook block reads and edits of secret-ish files, and
your existing config is git-committed before anything is written, so there is an
undo path. Full detail, and what to adjust if the defaults don't suit you:
[docs/security.md](docs/security.md).

## Install

One command per tool — run whichever you want, or both. All are idempotent —
safe to re-run, and anything already installed is skipped.

### 🪟 Windows

<details open>
<summary>PowerShell — show commands</summary>

**Claude Code**

```powershell
irm https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-windows.ps1 | iex
```

**Copilot CLI**

```powershell
irm https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-copilot-windows.ps1 | iex
```

</details>

### 🐧 WSL

<details>
<summary>bash, inside the distro — show commands</summary>

**Claude Code**

```bash
curl -fsSL https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-wsl.sh | bash
```

**Copilot CLI**

```bash
curl -fsSL https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-copilot-wsl.sh | bash
```

</details>

### 🍎 macOS

<details>
<summary>bash — show commands</summary>

**Claude Code**

```bash
curl -fsSL https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-macos.sh | bash
```

**Copilot CLI**

```bash
curl -fsSL https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-copilot-macos.sh | bash
```

</details>

## Prerequisites

**The CLI itself is installed for you.** Whichever installer you run puts the
`claude` or `copilot` CLI on your machine if it isn't there already, using that
tool's own official installer. Nothing already installed is upgraded, and you
log in with your own account either way.

**🪟 Windows** — `winget`, plus **an elevated PowerShell if Node.js is not yet
installed**, because the Node MSI cannot self-elevate. Nothing else needs
elevation.

**🐧 WSL** — `sudo`, `curl`, `tar`, and **`python3` already present**: it runs
every hook, and the installer stops early without it.

**🍎 macOS** — an admin account. Homebrew is installed if missing and will ask
for your password; **macOS 13+** is required for Copilot. The Claude installer
is [tested on Apple Silicon](claude/macos/README.md#tested-on-a-mac); for
Copilot the [`copilot-cli` cask install is still
unexercised](copilot/macos/README.md#partly-tested-on-a-mac).

## Passing flags

The full installer flag list is in each per-tool README, linked under
[Documentation](#documentation). The bootstrap itself takes one flag of its own
— `-Ref` on Windows, `--ref` on WSL and macOS — see
[Pinning to a fixed version](docs/security.md#pinning-to-a-fixed-version).

### 🪟 Windows

<details open>
<summary>build a scriptblock — show command</summary>

`| iex` cannot pass arguments, so pipe the script into a scriptblock instead:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-windows.ps1))) -SkipToolchain -SkipPlugins
```

</details>

### 🐧 WSL

<details>
<summary>after <code>-s --</code> — show command</summary>

Flags pass straight through:

```bash
curl -fsSL https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-wsl.sh | bash -s -- --skip-toolchain --skip-plugins
```

</details>

### 🍎 macOS

<details>
<summary>after <code>-s --</code> — show command</summary>

Same as WSL, with the macOS bootstrap:

```bash
curl -fsSL https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-macos.sh | bash -s -- --skip-toolchain --skip-plugins
```

</details>

## What you get

- **Claude Code** — 16 files in `~/.claude`: instructions, settings, two Python
  hooks, a statusline, the graphify skill.
- **Copilot CLI** — 10 files in `~/.copilot`: instructions, settings, LSP
  config, five Python hooks, hook registrations.

Plus the tools those settings need — `rtk`, `graphify`, `git`, Python, `jq`,
Node.js, the .NET SDK and three language servers — each installed only if it is
missing. On Windows, Rust is opt-in: pass `-WithRust`.

## Documentation

| | |
| --- | --- |
| [What it installs](docs/what-it-installs.md) | Every tool and why, the Rust story, the global instructions, skills, plugins |
| [Security and backups](docs/security.md) | Permissions, the deny list, the undo path, running remote code, pinning a version |
| [Architecture](docs/architecture.md) | Repo layout, the `shared/` overlay, how the instructions file is composed |

Per tool and platform — file lists, full flag tables, the `rtk` name collision,
and the exact restore command:

| | Windows | WSL | macOS |
| --- | --- | --- | --- |
| Claude Code | [claude/README.md](claude/README.md) | [claude/wsl](claude/wsl/README.md) | [claude/macos](claude/macos/README.md) |
| Copilot CLI | [copilot/README.md](copilot/README.md) | [copilot/wsl](copilot/wsl/README.md) | [copilot/macos](copilot/macos/README.md) |

## License

[MIT](LICENSE).
