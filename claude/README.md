# Claude Code user setup

A copy of a working Claude Code user-level setup: global instructions, settings,
hooks, a statusline and one skill — plus the command-line tools those settings
depend on. Everything lands in `~/.claude`. No credentials, chat history or
project memories are included; you log in with your own account.

## Prerequisites

- Windows 11 with `winget` available
- **An elevated PowerShell if Node.js is not yet installed** — the official
  Node.js MSI needs admin rights. If you already have `node`, a normal prompt
  is fine. Nothing else here needs elevation, Claude Code included.

Claude Code itself is installed if it's missing; you log in with your own
account.

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
| `-WithRust` | Install Rust: rustup + the stable toolchain, `rust-analyzer`, and the `rust-analyzer-lsp` plugin. Off by default — see [Rust is opt-in](#rust-is-opt-in). |
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
| `windows/config/settings.json` | Model `opus`, `effortLevel: high`, dark fullscreen TUI, telemetry off, autocompact at 60% of the context window. Deny-rules covering `.env`, `*.pem`, `*.key`, `secrets/`, `appsettings*.json`, `web.config`, `local.settings.json`, plus `git push`, `cd` and `pushd`. Wires up the hooks and statusline below, and enables the plugins — four with `-WithRust`, otherwise three, since `rust-analyzer-lsp` is removed for a no-Rust install. |
| `shared/hooks/check_sensitive_files.py` | PreToolUse hook. Hard-blocks Read/Edit/Write on secret-ish files (exits 2), independent of the deny-rules — belt and braces. |
| `shared/hooks/worktree_guard.py` | PreToolUse hook on Bash. Denies `git worktree add` anywhere outside `<cwd>/.claude/worktrees/` or `%TEMP%/claude/`, so worktrees stop landing in the workspace root or `C:\`. |
| `windows/config/statusline-command.ps1` | Statusline: ponytail marker, reasoning effort, then capsule pills for model/context, 5-hour and 7-day rate limits, followed by the logged-in account email and current git branch. |
| `shared/skills/graphify/` | The `graphify` skill — builds a queryable knowledge graph of a codebase — with its reference docs. Shipped as a snapshot, then refreshed by `graphify install --platform claude` so it matches the version actually installed. |
| `shared/RTK.md` | How `rtk` (the token-optimizing CLI proxy) works and its meta commands (`rtk gain`, `rtk discover`, `rtk proxy`). |
| `windows/setup-claude-windows.ps1` | The installer. |

### Why CLAUDE.md is split

Everything in it is platform-neutral except the closing `# bash on Windows`
section. Shipping the whole file per platform would triplicate the other ~70
lines across Windows, WSL and macOS, and they would drift apart. So the file is cut
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
| `rtk` | winget `rtk-ai.rtk` | **Required.** A hook rewrites every Bash tool call through `rtk hook claude`. Without it on PATH, every Bash call fails. A prebuilt binary — no Rust toolchain needed. Not the crates.io crate of the same name; see the warning below. |
| `graphify` | `uv tool install graphifyy` | Backs the bundled graphify skill and its two hooks. The PyPI package really is spelled with two y's. |
| `claude` | `https://claude.ai/install.ps1` | Claude Code itself. Anthropic's own installer: user scope, no elevation, SHA256-verified against a signed manifest. Only when missing — an existing install is never upgraded, and a running one is never replaced, because a running one isn't missing. |
| `git` | winget `Git.Git` | Used by the statusline and by the config backup step. |
| `py` 3.14 | winget `Python.PythonInstallManager` | Runs the two Python hooks. The script also makes sure a plain `python` resolves, since that is what the hook command uses. |
| Node.js LTS | Official MSI from nodejs.org | Resolved from the live release feed, not pinned. Needed for the TypeScript language server. |
| .NET SDK (LTS) | winget `Microsoft.DotNet.SDK.<major>` | Needed for `csharp-ls`. The LTS major is resolved at run time; checked by installed SDK major, not just whether `dotnet` exists — an existing .NET 8 or 9 does not satisfy it. |
| `rustup` | winget `Rustlang.Rustup` | **Only with `-WithRust`.** Provides `rust-analyzer`. |
| `jq` | winget `jqlang.jq` | General JSON wrangling. |
| `typescript-language-server` | `npm i -g` | Behind the `typescript-lsp` plugin. |
| `csharp-ls` | `dotnet tool install -g` | Behind the `csharp-lsp` plugin. |
| `rust-analyzer` | `rustup component add` | **Only with `-WithRust`.** Behind the `rust-analyzer-lsp` plugin. |

### Rust is opt-in

By default this installs **no Rust at all** — `rtk` is a prebuilt binary from
winget, so nothing else here needs a toolchain. That matters because rustup
pulls ~200 MB from `static.rust-lang.org`, and corporate web filters have been
seen to block those downloads outright, reporting them as a trojan.

`-WithRust` adds three things together, so config and installed tools always
agree:

| | Default | `-WithRust` |
| --- | --- | --- |
| rustup + stable toolchain | — | ✅ |
| `rust-analyzer` | — | ✅ |
| `rust-analyzer-lsp` plugin installed | — | ✅ |
| `rust-analyzer-lsp` in `settings.json` `enabledPlugins` | removed | kept |

The installer edits `enabledPlugins` as it stages `settings.json`, then parses
the result and compares the plugin sets, so a botched edit fails the run rather
than reaching Claude Code. Everything else in the file — `defaultMode`, all 21
deny rules, the hooks, the statusline — is untouched.

### Versions

Nothing you already have is upgraded — these only apply when a command is
missing. Most track latest automatically: `git`, `uv`, `jq`, `graphify`,
`typescript-language-server`, `csharp-ls`, `ponytail`, `rtk` (winget), and with
`-WithRust`, Rust (rustup stable). Node.js resolves the newest LTS from the live
release feed at run time.

One is pinned and needs a human bump eventually — override with a flag if you
want something else:

| Pin | Flag | Why |
| --- | --- | --- |
| Python 3.14 | `-PythonVersion` | Latest stable minor. Revisit when 3.15 ships. |

.NET is not pinned — the newest LTS still in active or maintenance support is
resolved at run time from Microsoft's official releases index.

### ⚠️ The `rtk` name collision

There are two unrelated tools called `rtk`. This setup needs
**[rtk-ai/rtk](https://github.com/rtk-ai/rtk)** (currently 0.45.x), the
token-optimizing proxy. The `rtk` crate on **crates.io is a different project** —
"Rust Type Kit", stuck at 0.1.0 — so `cargo install rtk` gets you the wrong one.

This matters because a hook pipes *every* Bash tool call through `rtk hook claude`.
With the wrong binary the subcommand doesn't exist and every Bash call in Claude
Code fails.

The winget package `rtk-ai.rtk` is the right one: its manifest is a portable zip
pointing at rtk-ai/rtk's own GitHub release asset, pinned by SHA256. The
installer verifies the result anyway by running `rtk gain`, which only the
correct tool supports — the presence of *an* `rtk` on PATH is deliberately not
treated as proof.

If you already have the crates.io `rtk`, winget installs its own copy **alongside
it**; unlike the old `cargo install --force`, it cannot overwrite the other one.
Which one wins is then a PATH question, and the two orders differ: the installer
prepends to the session PATH but Windows appends to the persisted one, so
`~\.cargo\bin` (often first) can shadow the winget shim in the next terminal you
open. The installer therefore ends by resolving `rtk` the way a **new** process
will — Machine PATH then User PATH — and running `rtk gain` on *that* copy. If the
wrong one would win, the run fails and names the file to delete, rather than
reporting success on a setup that breaks the moment you open a new terminal.

Plugins (installed via the `claude` CLI; if `claude` is not on PATH the script
prints the exact commands and continues, since `settings.json` already enables
them):

- `ponytail@ponytail` — from `DietrichGebert/ponytail`
- `typescript-lsp`, `csharp-lsp` — from `anthropics/claude-plugins-official`
- `rust-analyzer-lsp` — same marketplace, **only with `-WithRust`**

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

One setting is opinionated and worth a look:

- `permissions.defaultMode: "auto"` — tools auto-approve rather than prompting.

Claude Code's own dangerous-mode warning is left alone, so that prompt still
appears.

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
- **An existing repo is never reconfigured.** If `~/.claude` is already a git
  repo, the installer commits and nothing else: your `.gitignore` is not edited,
  and nothing is untracked. It is your repo — what it captures is your call.
  Adding an ignore rule would not untrack what is already there, but it *would*
  stop `git add` from picking up new files, so tomorrow's sessions would
  silently stop being backed up while yesterday's stayed. It does warn if the
  repo tracks `.credentials.json`, since those are live OAuth tokens, but it
  does not act — `git -C $HOME\.claude rm --cached .credentials.json` is yours
  to run. That check is the presence of `.git` in the directory itself, so it
  still holds when `.claude` is a junction or symlink into a dotfiles checkout.
- **A repo the installer creates gets a sensible `.gitignore`.** Credentials,
  setup residue, and bulk runtime state (`projects/`, `file-history/`,
  `history.jsonl`, `plugins/`, the caches) are excluded from the start, so a
  fresh machine never begins committing megabytes of session data that is no use
  as an undo point.

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
