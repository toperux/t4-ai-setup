# GitHub Copilot CLI user setup

A copy of a working Copilot CLI user-level setup: global instructions, settings,
LSP config and five hooks — plus the command-line tools those settings depend
on. Everything lands in `~/.copilot`. No credentials, chat history or project
memories are included; you log in with your own account.

## Prerequisites

- Windows 11 with `winget` available
- **An elevated PowerShell if Node.js is not yet installed** — the official
  Node.js MSI needs admin rights. If you already have `node`, a normal prompt
  is fine.

## Run it

```powershell
irm https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-copilot-windows.ps1 | iex
```

Or, from a checkout of this repo:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\setup-copilot-windows.ps1
```

Idempotent — safe to re-run. Anything already installed is skipped.

Flags (to pass these through the one-liner, see the
[root README](../README.md#passing-flags)):

| Flag | Effect |
| --- | --- |
| `-SkipToolchain` | Only copy the config; install no tools. |
| `-SkipPlugins` | Skip the `copilot plugin` installs. |
| `-SkipBackup` | Don't git-commit `~/.copilot` first. Overwrites with no undo path. Only needed if you're running `-SkipToolchain` on a machine without git. |
| `-CopilotDirectory <path>` | Write the config somewhere other than `~/.copilot`. |
| `-PythonVersion <x.y>` | Python version to install (default `3.14`). |
| `-SharedSource <path>` | The platform-neutral config tree (default `..\shared`). |
| `-ConfigSource <path>` | The platform overlay (default `.\config`). |

## What's in the package

Config is split in two: `shared/` holds everything that is identical on every
platform, `windows/config/` holds only what is Windows-specific. The installer
merges them, with the overlay winning on a collision.

| File | What it does |
| --- | --- |
| `shared/copilot-instructions.core.md` + `windows/config/copilot-instructions.append.md` | Global instructions loaded into every session: think before coding, simplicity first, surgical changes, goal-driven execution. Plus a terse-reporting preference and a Windows/Git-Bash rule about never putting `cd` in a compound command that also writes. **Composed into `~/.copilot/copilot-instructions.md` at install time** — see below. |
| `shared/settings.json` | Model `gpt-5.6-terra`, `effortLevel: high`, startup tips off, and a footer showing model effort, directory, branch, context window, quota, agent and sandbox. Enables the `ponytail@ponytail` plugin and registers its marketplace. No paths, no shell — portable as-is. |
| `shared/lsp-config.json` | Language servers for TypeScript/JS, C# and Rust, by bare command name (`typescript-language-server`, `csharp-ls`, `rust-analyzer`). |
| `shared/hooks/check_sensitive_files.py` | PreToolUse on Read/Edit/Write. Blocks secret-ish files — `.env`, `*.pem`, `*.key`, `secrets/`, `appsettings*.json`, `web.config`, `local.settings.json`. |
| `shared/hooks/command_policy.py` | PreToolUse on Bash. Blocks `git push` and bare `cd`. |
| `shared/hooks/worktree_guard.py` | PreToolUse on Bash. Denies `git worktree add` outside the allowed roots, so worktrees stop landing in the workspace root or `C:\`. |
| `shared/hooks/graphify_hint.py` | PreToolUse on Bash/Grep/Glob. Suggests `graphify query` before a text search. |
| `shared/hooks/graphify_update_notice.py` | PostToolUse on Edit/Write. Reminds you to run `graphify update .` so the graph stays current. |
| `shared/intellij-skills/debug/` | The `debug` skill. |
| `windows/config/hooks/copilot-hooks.json` | Registers the five hooks above. Windows-specific: every entry is keyed on `"powershell"` and uses `$env:USERPROFILE\...` paths. |
| `windows/config/hooks/rtk.json` | Routes shell commands through `rtk hook copilot`. Also keyed on `"powershell"`. |
| `windows/setup-copilot-windows.ps1` | The installer. |

### Why copilot-instructions.md is split

Everything in it is platform-neutral except the closing `# bash on Windows`
section. Shipping the whole file per platform would triplicate the other ~70
lines once WSL and macOS land, and they would drift apart. So the file is cut at
that heading — `shared/copilot-instructions.core.md` plus
`windows/config/copilot-instructions.append.md` — and the installer joins the
two **byte for byte**. The cut is a byte offset of the original, so
`core + append` reproduces it exactly: no re-encoding, no line-ending changes
(this file is CRLF throughout; the Claude one is LF).

Both halves are required. If the platform overlay has no
`copilot-instructions.append.md`, the installer stops rather than shipping
instructions that are missing a rule.

## What the installer installs

Command-line tools (each skipped if already on PATH):

| Tool | Via | Why |
| --- | --- | --- |
| `rtk` | `cargo install --git https://github.com/rtk-ai/rtk --locked` | **Required.** A hook rewrites shell commands through `rtk hook copilot`. Note it comes from **git, not crates.io** — see the warning below. |
| `graphify` | `uv tool install graphifyy` | Backs the two graphify hooks. The PyPI package really is spelled with two y's. |
| `copilot` | winget `GitHub.Copilot` | The Copilot CLI itself, if you don't already have it. You still log in with your own account. |
| `git` | winget `Git.Git` | Used by the config backup step. |
| `py` 3.14 | winget `Python.PythonInstallManager` | Runs the five Python hooks. The script also makes sure a plain `python` resolves, since that is what the hook commands use. |
| Node.js LTS | Official MSI from nodejs.org | Resolved from the live release feed and SHA256-verified. Needed for the TypeScript language server. |
| .NET SDK (LTS) | winget `Microsoft.DotNet.SDK.<major>` | Needed for `csharp-ls`. The LTS major is resolved at run time and checked by installed SDK major, not just whether `dotnet` exists. |
| `rustup` | winget `Rustlang.Rustup` | Provides `cargo` (for `rtk`) and `rust-analyzer`. |
| `jq` | winget `jqlang.jq` | General JSON wrangling. |
| `typescript-language-server` | `npm i -g` | Backs the `typescript` entry in `lsp-config.json`. |
| `csharp-ls` | `dotnet tool install -g` | Backs the `csharp` entry. |
| `rust-analyzer` | `rustup component add` | Backs the `rust` entry. |

### Versions

Nothing you already have is upgraded — these only apply when a command is
missing. Most track latest automatically: `copilot`, `git`, `uv`, `jq`, Rust
(rustup stable), `graphify`, `typescript-language-server`, `csharp-ls`,
`ponytail`, and `rtk` (git HEAD). Node.js and .NET resolve their newest LTS at
run time.

Python 3.14 is pinned and needs a human bump eventually — override with
`-PythonVersion`.

### ⚠️ The `rtk` name collision

There are two unrelated tools called `rtk`. This setup needs
**[rtk-ai/rtk](https://github.com/rtk-ai/rtk)** (currently 0.42.x), the
token-optimizing proxy. The `rtk` crate on **crates.io is a different project** —
"Rust Type Kit", stuck at 0.1.0 — so `cargo install rtk` gets you the wrong one.

This matters because `rtk.json` pipes shell commands through `rtk hook copilot`.
With the wrong binary the subcommand doesn't exist.

The installer therefore installs from git and verifies the result by running
`rtk gain`, which only the correct tool supports. If you already have the
crates.io `rtk`, it is replaced (with a warning).

Plugins (installed via the `copilot` CLI; if `copilot` is not on PATH the script
prints the exact commands and continues, since `settings.json` already enables
them):

- `ponytail@ponytail` — from `DietrichGebert/ponytail`

## What is deliberately NOT included

- Credentials — log in with your own account.
- Chat history, session transcripts and per-project state.
- Project memories — they are specific to someone else's codebases.

## Safety

- **Transactional copy.** Everything is staged first and swapped in at the end.
  If any step fails midway, your previous config is restored rather than left
  half-replaced.
- **Only shipped files are replaced.** `instructions/`, `prompts/` and `skills/`
  ship empty; the installer enumerates *files*, never directories, so anything
  you already have in those folders is left alone. (An earlier version replaced
  whole directories and deleted them.)
- **Node.js is checksum-verified** against the SHA256 nodejs.org publishes.
- **The backup repo is created in `~/.copilot` itself**, never a parent. If your
  home directory happens to be a git repo, this won't commit into it.

## Undo

Before writing anything, the installer commits your `~/.copilot` into a local
git repo *on your machine* (creating one if it isn't already a repo), so:

```powershell
git -C $HOME\.copilot log --oneline
git -C $HOME\.copilot checkout <commit-before-the-backup> -- .
```

The repo is local only and never pushed.
