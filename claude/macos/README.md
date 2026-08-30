# Claude Code user setup — macOS

A copy of a working Claude Code user-level setup: global instructions, settings,
hooks, a statusline and one skill — plus the command-line tools those settings
depend on. Everything lands in `~/.claude`. No credentials, chat history or
project memories are included; you log in with your own account.

Written for macOS on either architecture — Homebrew's prefix is resolved at run
time rather than hardcoded — and against the system `/bin/bash` 3.2 and BSD
userland, so no GNU coreutils are needed.

## Prerequisites

- macOS with an admin account. Homebrew is installed if it is missing, and its
  installer will ask for your password.
- `curl` and `tar`, both of which ship with macOS.
- Nothing else. Claude Code itself is installed if it's missing; you log in with
  your own account.

## Run it

```bash
curl -fsSL https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-macos.sh | bash
```

Flags pass straight through after `-s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-macos.sh | bash -s -- --skip-toolchain
```

Or, from a checkout of this repo:

```bash
bash claude/macos/setup-claude-macos.sh
```

Idempotent — safe to re-run. Anything already installed is skipped.

| Flag | Effect |
| --- | --- |
| `--skip-toolchain` | Only copy the config; install no tools. |
| `--skip-plugins` | Skip the `claude plugin` installs. |
| `--skip-backup` | Don't git-commit `~/.claude` first. Overwrites with no undo path. Only needed if you're running `--skip-toolchain` on a machine without git. |
| `--claude-dir <path>` | Write the config somewhere other than `~/.claude`. |
| `--shared-source <path>` | The platform-neutral config tree (default `../shared`). |
| `--config-source <path>` | The platform overlay (default `./config`). |
| `--ref <ref>` | *(bootstrap only)* Branch, tag or SHA to install from. |

## What's in the package

Config is split in two: `shared/` holds everything that is identical on every
platform, `macos/config/` holds only what differs. The installer merges them,
with the overlay winning on a collision.

| File | What it does |
| --- | --- |
| `shared/CLAUDE.core.md` + `macos/config/CLAUDE.append.md` | Global instructions loaded into every session: think before coding, simplicity first, surgical changes, goal-driven execution. Plus a terse-reporting preference and a macOS note about the BSD userland, bash 3.2, the case-insensitive filesystem and `brew --prefix`. **Composed into `~/.claude/CLAUDE.md` at install time** — see below. |
| `macos/config/settings.json` | Model `opus`, `effortLevel: high`, dark fullscreen TUI, autocompact at 60% of the context window. Deny-rules covering `.env`, `*.pem`, `*.key`, `secrets/`, `appsettings*.json`, `web.config`, `local.settings.json`, plus `git push`. Wires up the hooks and statusline below, and enables the four plugins. |
| `shared/hooks/check_sensitive_files.py` | PreToolUse hook. Hard-blocks Read/Edit/Write on secret-ish files (exits 2), independent of the deny-rules — belt and braces. |
| `shared/hooks/worktree_guard.py` | PreToolUse hook on Bash. Denies `git worktree add` outside the allowed roots, so worktrees stop landing in the workspace root. |
| `macos/config/statusline-command.sh` | Statusline: ponytail marker, reasoning effort, then capsule pills for model/context, 5-hour and 7-day rate limits, followed by account email and current git branch. Needs `python3`. |
| `shared/skills/graphify/` | The `graphify` skill — builds a queryable knowledge graph of a codebase — with its reference docs. Shipped as a snapshot, then refreshed by `graphify install --platform claude` so it matches the version actually installed. |
| `shared/RTK.md` | How `rtk` (the token-optimizing CLI proxy) works and its meta commands. |
| `macos/setup-claude-macos.sh` | The installer. |

`settings.json` and `statusline-command.sh` are byte-identical to the WSL
overlay's today. They are still duplicated rather than promoted into `shared/`,
because `shared/` means "correct on every platform" and neither file is: the
Windows overlay replaces both. Promoting the statusline would also ship a stray
`.sh` into `~/.claude` on Windows, since the merge is a union.

### Why CLAUDE.md is split

Everything in it is platform-neutral except the closing shell section. Shipping
the whole file per platform would triplicate the other ~70 lines across Windows,
WSL and macOS, and they would drift apart. So the file is cut at that heading —
`shared/CLAUDE.core.md` plus `macos/config/CLAUDE.append.md` — and the installer
joins the two with `cat`, byte for byte.

Both halves are required. If the overlay has no `CLAUDE.append.md`, the
installer stops rather than shipping instructions that are missing a rule.

## How this differs from the other packages

Same 16 files, same behaviour. The deltas:

| | Windows | WSL | macOS |
| --- | --- | --- | --- |
| Hook interpreter | `python` | `python3` | `python3` |
| Statusline | `statusline-command.ps1` | `statusline-command.sh` | `statusline-command.sh` |
| `Bash(cd *)` / `Bash(pushd *)` deny-rules | present | absent | absent — they exist for Git Bash's unstatic cwd, which is a Windows problem |
| Package manager | `winget` + the official Node MSI | `apt`/`dnf`/`pacman`/`zypper` | Homebrew |
| .NET SDK | winget, LTS major resolved at run time | distro packages, newest LTS first | `dotnet-install.sh --channel LTS` |

## What the installer installs

Each is skipped if already on PATH:

| Tool | Via | Why |
| --- | --- | --- |
| Homebrew | `raw.githubusercontent.com/Homebrew/install` | Everything below it. `brew shellenv` is also **persisted** to your profile, which the Homebrew installer itself only prints as an instruction. |
| `claude` | `curl -fsSL https://claude.ai/install.sh \| bash` | Claude Code itself. The plugin step can do nothing without it. |
| `rtk` | `cargo install --git https://github.com/rtk-ai/rtk --locked` | **Required.** A hook routes every Bash tool call through `rtk hook claude`. From **git, not crates.io** — see the warning below. |
| `graphify` | `uv tool install graphifyy` | Backs the bundled skill and its two hooks. The PyPI package really is spelled with two y's. |
| `git`, `jq`, `python`, `uv`, `node` | `brew install` | Backup step, JSON wrangling, hooks, graphify, the TypeScript server. |
| `rustup` | `sh.rustup.rs` | Provides `cargo` (for `rtk`) and `rust-analyzer`. From rustup.rs rather than Homebrew so `rustup component add` behaves as it does on the other platforms. |
| .NET SDK | `dotnet-install.sh --channel LTS` | Needed for `csharp-ls`. Microsoft's own script, and `LTS` is a first-class channel meaning "the most recent Long Term Support release" — so the version policy is named directly and needs no editing when .NET 11 ships. Installs under `$HOME/.dotnet` with no `sudo`. Best-effort; `csharp-ls` is the only casualty if it doesn't land. |
| `typescript-language-server` | `npm i -g` | Behind the `typescript-lsp` plugin. |
| `csharp-ls` | `dotnet tool install -g` | Behind the `csharp-lsp` plugin. |
| `rust-analyzer` | `rustup component add` | Behind the `rust-analyzer-lsp` plugin. |

`$HOME/.cargo/bin`, `$HOME/.local/bin`, `$HOME/.dotnet` and `$HOME/.dotnet/tools`
are added to `~/.zprofile` — always, since zsh has been the login shell since
Catalina, so it is written whether or not it already exists — and also to
`~/.zshrc`, `~/.bash_profile` and `~/.profile` if those exist. Directories
outside `$HOME` are never persisted; the Homebrew prefix is already handled by
`brew shellenv`.

`DOTNET_ROOT=$HOME/.dotnet` is exported and persisted the same way, but only
when this script is the one that installed the SDK. `dotnet-install.sh` puts it
somewhere macOS does not look by default, and a global tool's launcher can't
find its runtime without that variable.

### ⚠️ The `rtk` name collision

There are two unrelated tools called `rtk`. This setup needs
**[rtk-ai/rtk](https://github.com/rtk-ai/rtk)**, the token-optimizing proxy. The
`rtk` crate on **crates.io is a different project** — "Rust Type Kit", stuck at
0.1.0 — so `cargo install rtk` gets you the wrong one.

This matters because a hook pipes *every* Bash tool call through
`rtk hook claude`. With the wrong binary every Bash call fails. The installer
installs from git and verifies with `rtk gain`, which only the correct tool
supports. If you already have the crates.io `rtk`, it is replaced (with a
warning).

### A note on `python3`

`/usr/bin/python3` exists on a Mac with no Command Line Tools, but it is a stub
that only prompts to install them when run. So the installer *executes* python3
rather than looking for it on PATH, and Homebrew's `python` is installed if that
probe fails.

## Safety

- **Transactional copy.** Everything is staged, then swapped in, tracking what
  was replaced. If any step fails midway the previous config is restored and the
  script exits non-zero, rather than leaving `~/.claude` half-replaced.
- **Only shipped files are touched.** The installer enumerates *files*, never
  directories, so your own hooks and skills are left alone.
- **The backup repo is created in `~/.claude` itself**, never a parent — a
  dotfiles setup where `$HOME` is already a git repo won't get an unrelated
  commit.
- **An existing repo is never reconfigured.** If `~/.claude` is already a git
  repo, the installer commits and nothing else: your `.gitignore` is not edited,
  and nothing is untracked. It is your repo — what it captures is your call.
  Adding an ignore rule would not untrack what is already there, but it *would*
  stop `git add` from picking up new files, so tomorrow's sessions would
  silently stop being backed up while yesterday's stayed. It does warn if the
  repo tracks `.credentials.json`, since those are live OAuth tokens, but it
  does not act — `git -C ~/.claude rm --cached .credentials.json` is yours to
  run. That check is the presence of `.git` in the directory itself, so it still
  holds when `~/.claude` is a symlink into a dotfiles checkout.
- **A repo the installer creates gets a sensible `.gitignore`.** Credentials,
  setup residue, bulk runtime state (`projects/`, `file-history/`,
  `history.jsonl`, `plugins/`, the caches) and `.DS_Store` are excluded from the
  start, so a fresh machine never begins committing megabytes of session data
  that is no use as an undo point.

## Undo

Before writing anything, the installer commits your `~/.claude` into a local git
repo, so:

```bash
git -C ~/.claude log --oneline
git -C ~/.claude checkout <commit-before-the-backup> -- .
```

The repo is local only and never pushed.

## Tested on a Mac

This installer has been run end-to-end on macOS hardware — Apple Silicon, on a
machine with no Homebrew, so the bootstrap really did run — and it works. That
covers the parts that used to be listed here as unverified: the Homebrew
install, persisting `brew shellenv` to the profile, `dotnet-install.sh --channel
LTS`, the `claude` install, and building `rtk` with `cargo`.

Also verified, and still worth knowing:

- **The whole script runs on a real bash 3.2** — the version macOS ships as
  `/bin/bash`, and what `bash setup-claude-macos.sh` resolves to on a Mac
  without Homebrew's bash. Built from source specifically to test this rather
  than assumed from reading. It parses, installs, re-runs idempotently, rolls
  back correctly when the swap is made to fail partway, and renders `--help`.
  The one construct that genuinely differs on 3.2 — expanding an empty array
  under `set -u`, which `rollback()` does at its worst moment — was checked
  directly.
- Everything platform-neutral: the config merge, the composed `CLAUDE.md`, the
  transactional swap and rollback, and the plugin matcher all come from the WSL
  installer unchanged and are covered by its test run.

One caveat remains: only the Apple Silicon layout has been exercised. Homebrew's
prefix is resolved at run time by trying `/opt/homebrew` then `/usr/local`, and
the `/usr/local` branch — the Intel layout — has still never run on hardware.
