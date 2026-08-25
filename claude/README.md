# Claude Code user setup

A copy of a working Claude Code user-level setup: global instructions, settings,
hooks, a statusline and one skill — plus the command-line tools those settings
depend on. Everything lands in `~/.claude`. No credentials, chat history or
project memories are included; you log in with your own account.

## Prerequisites

- Windows 11 with `winget` available
- Claude Code already installed and logged in (`claude --version` works)
- **An elevated PowerShell if Node.js is not yet installed** — the official
  Node.js MSI needs admin rights. If you already have `node`, a normal prompt
  is fine.

## Run it

```powershell
irm https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-windows.ps1 | iex
```

Or, from a checkout of this repo:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\setup-claude-windows.ps1
```

Idempotent — safe to re-run. Anything already installed is skipped.

Flags (to pass these through the one-liner, see the
[root README](../README.md#passing-flags)):

| Flag | Effect |
| --- | --- |
| `-SkipToolchain` | Only copy the config; install no tools. |
| `-SkipPlugins` | Skip the `claude plugin` installs. |
| `-SkipBackup` | Don't git-commit `~/.claude` first. Overwrites with no undo path. Only needed if you're running `-SkipToolchain` on a machine without git. |
| `-ClaudeDirectory <path>` | Write the config somewhere other than `~/.claude`. |
| `-PythonVersion <x.y>` | Python version to install (default `3.14`). |
| `-SharedSource <path>` | The platform-neutral config tree (default `..\shared`). |
| `-ConfigSource <path>` | The platform overlay (default `.\config`). |

## What's in the package

Config is split in two: `shared/` holds everything that is identical on every
platform, `windows/config/` holds only what is Windows-specific. The installer
merges them, with the overlay winning on a collision.

| File | What it does |
| --- | --- |
| `shared/CLAUDE.core.md` + `windows/config/CLAUDE.append.md` | Global instructions loaded into every session: think before coding, simplicity first, surgical changes, goal-driven execution. Plus a terse-reporting preference and a Windows/Git-Bash rule about never putting `cd` in a compound command that also writes. **Composed into `~/.claude/CLAUDE.md` at install time** — see below. |
| `windows/config/settings.json` | Model `opus`, `effortLevel: high`, dark fullscreen TUI, telemetry off, autocompact at 60% of the context window. Deny-rules covering `.env`, `*.pem`, `*.key`, `secrets/`, `appsettings*.json`, `web.config`, `local.settings.json`, plus `git push`, `cd` and `pushd`. Wires up the hooks and statusline below, and enables the four plugins. |
| `shared/hooks/check_sensitive_files.py` | PreToolUse hook. Hard-blocks Read/Edit/Write on secret-ish files (exits 2), independent of the deny-rules — belt and braces. |
| `shared/hooks/worktree_guard.py` | PreToolUse hook on Bash. Denies `git worktree add` anywhere outside `<cwd>/.claude/worktrees/` or `%TEMP%/claude/`, so worktrees stop landing in the workspace root or `C:\`. |
| `windows/config/statusline-command.ps1` | Statusline: model name, context-usage bar, 5-hour and 7-day rate-limit bars, logged-in account email, current git branch. |
| `shared/skills/graphify/` | The `graphify` skill — builds a queryable knowledge graph of a codebase — with its reference docs. Shipped as a snapshot, then refreshed by `graphify install --platform claude` so it matches the version actually installed. |
| `shared/RTK.md` | How `rtk` (the token-optimizing CLI proxy) works and its meta commands (`rtk gain`, `rtk discover`, `rtk proxy`). |
| `windows/setup-claude-windows.ps1` | The installer. |

### Why CLAUDE.md is split

Everything in it is platform-neutral except the closing `# bash on Windows`
section. Shipping the whole file per platform would triplicate the other ~70
lines once WSL and macOS land, and they would drift apart. So the file is cut
at that heading — `shared/CLAUDE.core.md` plus `windows/config/CLAUDE.append.md`
— and the installer joins the two **byte for byte**. The cut is a byte offset of
the original, so `core + append` reproduces it exactly: no re-encoding, no
line-ending changes.

Both halves are required. If the platform overlay has no `CLAUDE.append.md`,
the installer stops rather than shipping instructions that are missing a rule.

## What the installer installs

Command-line tools (each skipped if already on PATH):

| Tool | Via | Why |
| --- | --- | --- |
| `rtk` | `cargo install --git https://github.com/rtk-ai/rtk --locked` | **Required.** A hook rewrites every Bash tool call through `rtk hook claude`. Without it on PATH, every Bash call fails. Note it comes from **git, not crates.io** — see the warning below. |
| `graphify` | `uv tool install graphifyy` | Backs the bundled graphify skill and its two hooks. The PyPI package really is spelled with two y's. |
| `git` | winget `Git.Git` | Used by the statusline and by the config backup step. |
| `py` 3.14 | winget `Python.PythonInstallManager` | Runs the two Python hooks. The script also makes sure a plain `python` resolves, since that is what the hook command uses. |
| Node.js LTS | Official MSI from nodejs.org | Resolved from the live release feed, not pinned. Needed for the TypeScript language server. |
| .NET SDK (LTS) | winget `Microsoft.DotNet.SDK.<major>` | Needed for `csharp-ls`. The LTS major is resolved at run time; checked by installed SDK major, not just whether `dotnet` exists — an existing .NET 8 or 9 does not satisfy it. |
| `rustup` | winget `Rustlang.Rustup` | Provides `cargo` (for `rtk`) and `rust-analyzer`. |
| `jq` | winget `jqlang.jq` | General JSON wrangling. |
| `typescript-language-server` | `npm i -g` | Behind the `typescript-lsp` plugin. |
| `csharp-ls` | `dotnet tool install -g` | Behind the `csharp-lsp` plugin. |
| `rust-analyzer` | `rustup component add` | Behind the `rust-analyzer-lsp` plugin. |

### Versions

Nothing you already have is upgraded — these only apply when a command is
missing. Most track latest automatically: `git`, `uv`, `jq`, Rust (rustup
stable), `graphify`, `typescript-language-server`, `csharp-ls`, `ponytail`, and
`rtk` (git HEAD). Node.js resolves the newest LTS from the live release feed at
run time.

Two are pinned and need a human bump eventually — override with a flag if you
want something else:

| Pin | Flag | Why |
| --- | --- | --- |
| Python 3.14 | `-PythonVersion` | Latest stable minor. Revisit when 3.15 ships. |

.NET is no longer pinned — the newest LTS still in active or maintenance
support is resolved at run time from Microsoft's official releases index.

### ⚠️ The `rtk` name collision

There are two unrelated tools called `rtk`. This setup needs
**[rtk-ai/rtk](https://github.com/rtk-ai/rtk)** (currently 0.42.x), the
token-optimizing proxy. The `rtk` crate on **crates.io is a different project** —
"Rust Type Kit", stuck at 0.1.0 — so `cargo install rtk` gets you the wrong one.

This matters because a hook pipes *every* Bash tool call through `rtk hook claude`.
With the wrong binary the subcommand doesn't exist and every Bash call in Claude
Code fails.

The installer therefore installs from git and verifies the result by running
`rtk gain`, which only the correct tool supports. If you already have the
crates.io `rtk`, it is replaced (with a warning).

Plugins (installed via the `claude` CLI; if `claude` is not on PATH the script
prints the exact commands and continues, since `settings.json` already enables
them):

- `ponytail@ponytail` — from `DietrichGebert/ponytail`
- `typescript-lsp`, `csharp-lsp`, `rust-analyzer-lsp` — from `anthropics/claude-plugins-official`

## What is deliberately NOT included

- `.credentials.json` — OAuth tokens. Log in with your own account.
- `.claude.json` — user ID, machine ID, account details, per-project history.
- `history.jsonl`, `projects/`, `sessions/`, `shell-snapshots/` — chat history
  and session transcripts.
- All project memories (`projects/*/memory/`) — they are specific to someone
  else's codebases.
- The plugin cache — reinstalled from the marketplaces instead, so no stale
  absolute paths.

## Before your first run

Two settings are opinionated and worth a look:

- `permissions.defaultMode: "auto"` — tools auto-approve rather than prompting.
- `skipDangerousModePermissionPrompt: true` — suppresses the dangerous-mode warning.

The deny-list also assumes .NET / Azure Functions projects (`appsettings.json`,
`web.config`, `local.settings.json`). Skim `windows/config/settings.json` and
adjust before running if any of that doesn't suit you.

## Safety

- **Transactional copy.** Everything is staged first and swapped in at the end.
  If any step fails midway, your previous config is restored rather than left
  half-replaced.
- **Node.js is checksum-verified.** The MSI is matched against the SHA256 that
  nodejs.org publishes before it is executed.
- **The backup repo is created in `~/.claude` itself**, never a parent. If your
  home directory happens to be a git repo, this won't commit into it.

## A note on CLAUDE.md and graphify

The installer runs `graphify install --platform claude` (user level) so the
skill matches the installed tool rather than the bundled snapshot. That command
appends a registration block to `CLAUDE.md`:

```
# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge
  graph. Trigger: `/graphify`
When the user types `/graphify`, use the installed graphify skill ...
```

The installer strips that block again, because it is redundant here: Claude Code
discovers skills from `~/.claude/skills/` on its own, and the two graphify hooks
in `settings.json` already prompt for `graphify query` before searching and
`graphify update .` after edits. Stripping it on every run also keeps re-runs
from re-adding it, so `CLAUDE.md` stays as written.

## What it leaves alone

`settings.json`, `CLAUDE.md` and `RTK.md` are overwritten, but only the specific
hooks and skills this package ships are replaced — `hooks/check_sensitive_files.py`,
`hooks/worktree_guard.py` and `skills/graphify/`. Any other hooks or skills you
already have in `~/.claude` are left in place.

## Undo

Before writing anything, the installer commits your `~/.claude` into a local git
repo *on your machine* (creating one if it isn't already a repo), so:

```powershell
git -C $HOME\.claude log --oneline
git -C $HOME\.claude checkout <commit-before-the-backup> -- .
```

The repo is local only and never pushed. `.credentials.json` is gitignored.
