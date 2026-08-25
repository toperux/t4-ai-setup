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
| macOS | ✅ — [detail](claude/macos/README.md) (untested on hardware) | ⏳ planned — [notes](copilot/macos/README.md) |

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

**Claude Code — macOS** (bash):

```bash
curl -fsSL https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-macos.sh | bash
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

**macOS:**

- An admin account. Homebrew is installed if missing and will ask for your
  password; `curl` and `tar` already ship with the OS.
- Nothing else — this is the one installer that **does** install the `claude`
  CLI for you. You still log in yourself.
- ⚠️ **Untested on macOS hardware.** The platform-neutral half is covered by the
  WSL test run; the Homebrew, `dotnet-sdk` cask and `claude` steps are not. See
  [`claude/macos/README.md`](claude/macos/README.md).

### Passing flags

On Windows, `| iex` cannot pass arguments, so build a scriptblock instead:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-windows.ps1))) -SkipToolchain -SkipPlugins
```

On WSL and macOS, flags pass straight through after `-s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-wsl.sh | bash -s -- --skip-toolchain --skip-plugins
```

The full installer flag list is in [`claude/README.md`](claude/README.md),
[`claude/wsl/README.md`](claude/wsl/README.md),
[`claude/macos/README.md`](claude/macos/README.md) and
[`copilot/README.md`](copilot/README.md). The bootstrap itself takes one flag of
its own — `-Ref` on Windows, `--ref` on WSL and macOS — see
[Pinning to a fixed version](#pinning-to-a-fixed-version).

## What each installer does

- **Claude Code** — writes 16 files into `~/.claude` (instructions, settings,
  two Python hooks, a statusline, the graphify skill) and installs the tools
  those settings need. Detail: [`claude/README.md`](claude/README.md) for
  Windows, [`claude/wsl/README.md`](claude/wsl/README.md) for WSL,
  [`claude/macos/README.md`](claude/macos/README.md) for macOS.
- **Copilot CLI** — writes 11 files into `~/.copilot` (instructions, settings,
  LSP config, five Python hooks, hook registrations) and the same toolchain.
  Detail: [`copilot/README.md`](copilot/README.md).

Neither installer upgrades a tool you already have; version policy only applies
when a command is missing. Both git-commit your existing `~/.claude` /
`~/.copilot` into a local repo before writing anything, so there is an undo
path.

### Tools it checks for, and installs only if missing

Each one is probed on PATH first and skipped if it is already there. Sources
differ by platform — winget plus the official Node MSI on Windows,
apt/dnf/pacman/zypper plus `rustup` and `uv` on WSL, Homebrew on macOS.

| Tool | Why | Claude | Copilot |
| --- | --- | :-: | :-: |
| `rtk` | **Required.** A hook routes every shell command through `rtk hook` — a token-optimizing CLI proxy that claims 60–90% savings on dev operations. Installed **from git, not crates.io**; the crates.io `rtk` is an unrelated project. | ✅ | ✅ |
| `graphify` | Backs the graphify skill (Claude) and the two graphify hooks (Copilot). The PyPI package is spelled `graphifyy`. | ✅ | ✅ |
| The CLI itself | The Copilot installer installs `copilot`. The Claude installer installs `claude` **on macOS only** — on Windows and WSL, bring your own, already logged in. Either way you log in yourself. | macOS | ✅ |
| Homebrew | macOS only, and everything else depends on it. `brew shellenv` is persisted to your profile, which Homebrew's own installer only prints as an instruction. | macOS | — |
| `git` | The pre-write config backup — and, for Claude, the statusline's branch segment. | ✅ | ✅ |
| Python | Runs the hooks — two for Claude, five for Copilot. Windows installs 3.14, macOS installs Homebrew's; **on WSL `python3` must already exist** and the installer stops early if it doesn't. | ✅ | ✅ |
| `jq` | General JSON wrangling. On WSL, `curl` too. | ✅ | ✅ |
| Node.js LTS | Only to provide `typescript-language-server`. | ✅ | ✅ |
| .NET SDK (LTS) | Only to provide `csharp-ls`. The LTS major is resolved at run time — except on macOS, where Homebrew ships a single `dotnet-sdk` cask tracking the current release. | ✅ | ✅ |
| `rustup` | Provides `cargo` (which builds `rtk`) and `rust-analyzer`. | ✅ | ✅ |
| `typescript-language-server`, `csharp-ls`, `rust-analyzer` | The three language servers the LSP plugins and `lsp-config.json` drive. | ✅ | ✅ |

### What's in the global instructions

`CLAUDE.md` / `copilot-instructions.md` are the same document, and it is short —
four behavioural rules plus two notes:

- **Think before coding** — state assumptions, surface multiple readings rather
  than silently picking one, say so when a simpler approach exists.
- **Simplicity first** — the minimum code that solves the problem; no
  speculative features, abstractions or configurability.
- **Surgical changes** — touch only what the request requires, match the
  surrounding style, don't refactor what isn't broken, clean up only orphans
  your own change created.
- **Goal-driven execution** — turn the task into a verifiable goal and state a
  short plan with a check per step.
- **A reporting preference** — terse, outlined, no sycophancy.
- **A pointer to `RTK.md`**, so the model knows its shell commands are being
  rewritten and what the `rtk` meta commands are.

The closing section is the only platform-specific part, and is swapped per
platform: Git Bash's unstatic cwd on Windows, `/mnt/c` performance and
`wslpath` on WSL.

### Skills

- **`graphify`** (Claude) — turns a codebase into a persistent, queryable
  knowledge graph and answers architecture and file-relationship questions from
  it instead of grepping. Shipped as a snapshot, then refreshed from your
  installed `graphify` so the two versions match.
- **`debug`** (Copilot) — drives the JetBrains IDE debugger to find the root
  cause of a crash or unexpected runtime behaviour.

### Plugins

Enabled in `settings.json` and installed from `anthropics/claude-plugins-official`
and `DietrichGebert/ponytail` — Copilot uses only the latter:

| Plugin | What it does | Claude | Copilot |
| --- | --- | :-: | :-: |
| `ponytail` | "Forces the laziest solution that works. YAGNI, stdlib first, one line over fifty." Reinforces the simplicity rule above. | ✅ | ✅ |
| `typescript-lsp` | TypeScript/JavaScript code intelligence. | ✅ | — |
| `csharp-lsp` | C# code intelligence. | ✅ | — |
| `rust-analyzer-lsp` | Rust code intelligence. | ✅ | — |

Copilot gets the same three language servers through `lsp-config.json` rather
than through plugins. Pass `-SkipPlugins` / `--skip-plugins` to skip this step
entirely; the settings still enable them, so a first session would fetch them.

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
install-claude-macos.sh
install-copilot-windows.ps1
claude/
  shared/                      config that is the same on every platform
  windows/
    setup-claude-windows.ps1   the installer
    config/                    the Windows-only config
  wsl/
    setup-claude-wsl.sh
    config/                    the WSL-only config
  macos/
    setup-claude-macos.sh
    config/                    the macOS-only config
copilot/                       same shape, Windows only so far
```

The Windows bootstrap downloads a zip; the WSL and macOS ones download a
tarball, because `tar` is everywhere while `unzip` often isn't — and unlike the
zip, the tarball preserves the executable bit.

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
