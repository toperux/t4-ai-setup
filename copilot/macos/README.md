# GitHub Copilot CLI user setup for macOS

A copy of a working Copilot CLI user-level setup: global instructions, settings,
LSP config and five hooks — plus the command-line tools those settings depend
on. Everything lands in `~/.copilot`. No credentials, chat history or project
memories are included; you log in with your own account.

macOS port of [`../windows/setup-copilot-windows.ps1`](../windows), built from
the [WSL port](../wsl). Everything platform-neutral is shared with both — see
[`../shared/`](../shared).

## Prerequisites

- macOS on Apple Silicon or Intel; both Homebrew prefixes are handled
- **macOS 13 (Ventura) or newer** — the `copilot-cli` cask declares
  `depends_on macos: ">= 13"`. On anything older the cask install fails, the
  script warns and carries on, and you end up with the config but no `copilot`
  binary. Install it another way (`npm i -g @github/copilot`, Node 22+) and
  re-run.
- An admin password, once, if Homebrew is not already installed

Homebrew, `python3` and the Copilot CLI are all installed for you. The cask is a
plain `binary` symlink into the Homebrew prefix, so that part needs no password.

## Run it

```bash
curl -fsSL https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-copilot-macos.sh | bash
```

Or, from a checkout of this repo:

```bash
bash copilot/macos/setup-copilot-macos.sh
```

Idempotent — safe to re-run. Anything already installed is skipped.

Flags (to pass these through the one-liner, see the
[root README](../../README.md#passing-flags)):

| Flag | Effect |
| --- | --- |
| `--skip-toolchain` | Only copy the config; install no tools. Requires a working `python3` already. |
| `--skip-plugins` | Skip the `copilot plugin` installs. |
| `--skip-backup` | Don't git-commit `~/.copilot` first. Overwrites with no undo path. |
| `--copilot-dir <path>` | Write the config somewhere other than `~/.copilot`. |
| `--shared-source <path>` | The platform-neutral config tree (default `../shared`). |
| `--config-source <path>` | The platform overlay (default `./config`). |

## What's in the package

Config is split in two: `shared/` holds everything identical on every platform,
`macos/config/` holds only what is macOS-specific. The installer merges them,
with the overlay winning on a collision.

| File | What it does |
| --- | --- |
| `shared/copilot-instructions.core.md` + `macos/config/copilot-instructions.append.md` | Global instructions loaded into every session: think before coding, simplicity first, surgical changes, goal-driven execution. Plus a terse-reporting preference and a macOS note on BSD vs GNU tool flags, bash 3.2, the case-insensitive filesystem, and `brew --prefix`. **Composed into `~/.copilot/copilot-instructions.md` at install time.** |
| `shared/settings.json` | Model `gpt-5.6-terra`, `effortLevel: high`, startup tips off, and a footer showing model effort, directory, branch, context window, quota, agent and sandbox. Enables the `ponytail@ponytail` plugin and registers its marketplace. No paths, no shell — portable as-is. |
| `shared/lsp-config.json` | Language servers for TypeScript/JS, C# and Rust, by bare command name. |
| `shared/hooks/check_sensitive_files.py` | PreToolUse on Read/Edit/Write. Blocks secret-ish files — `.env`, `*.pem`, `*.key`, `secrets/`, `appsettings*.json`, `web.config`, `local.settings.json`. |
| `shared/hooks/command_policy.py` | PreToolUse on Bash. Blocks `git push` and bare `cd`. |
| `shared/hooks/worktree_guard.py` | PreToolUse on Bash. Denies `git worktree add` outside the allowed roots. |
| `shared/hooks/graphify_hint.py` | PreToolUse on Bash/Grep/Glob. Suggests `graphify query` before a text search. |
| `shared/hooks/graphify_update_notice.py` | PostToolUse on Edit/Write. Reminds you to run `graphify update .`. |
| `macos/config/hooks/copilot-hooks.json` | Registers the five hooks above, keyed on `"bash"` and calling `python3 "<copilot-dir>/hooks/…"`, rendered from `__COPILOT_HOME__` at install time so `--copilot-dir` is honoured. |
| `macos/config/hooks/rtk.json` | Routes shell commands through `rtk hook copilot`, also keyed on `"bash"`. |
| `macos/setup-copilot-macos.sh` | The installer. |

The two hook files are byte-identical to the WSL overlay's but stay duplicated:
`shared/` means "correct on every platform" and these are not, since Windows
replaces both. See [the WSL README](../wsl/README.md#why-the-two-hook-files-use-different-naming)
for why the two files use different event-name conventions — both are correct.

### Why copilot-instructions.md is split

Everything in it is platform-neutral except the closing `# bash on …` section,
so the file is cut at that heading and the installer joins the two halves
**byte for byte**. This file is **CRLF throughout** (the Claude one is LF), and
the appendix here is CRLF to match — the installer checks the result and warns
if a bare LF appears. Both halves are required; a missing appendix is a hard
stop rather than a silently truncated instruction file.

## What the installer installs

Each is skipped if already on PATH. Nothing you already have is upgraded.

| Tool | Via | Why |
| --- | --- | --- |
| Homebrew | `raw.githubusercontent.com/Homebrew/install` | Everything below it. `brew shellenv` is also **persisted** to your profile, which the Homebrew installer itself only prints as an instruction. The prefix is discovered, not hardcoded, so Apple Silicon and Intel both work. |
| `copilot` | `brew install --cask copilot-cli` | The Copilot CLI. The cask rather than the WSL port's install script: on a machine that already has Homebrew this is the route GitHub documents for macOS, and `brew upgrade` keeps working afterwards. You still log in with your own account. Note its `zap` stanza trashes `~/.copilot`, so `brew uninstall --zap copilot-cli` takes this config with it — a plain `brew uninstall` does not. |
| `rtk` | `cargo install --git https://github.com/rtk-ai/rtk --locked` | **Required.** A hook routes shell commands through `rtk hook copilot`. From **git, not crates.io** — see the warning below. |
| `graphify` | `uv tool install graphifyy` | Backs the two graphify hooks. The PyPI package really is spelled with two y's. |
| `git`, `jq`, `python`, `uv`, `node` | `brew install` | Backup step, JSON wrangling, the five hooks, graphify, the TypeScript server. |
| `rustup` | `sh.rustup.rs` | From rustup.rs rather than Homebrew, so `rustup component add` works the same way it does on the other two platforms. |
| .NET SDK | `dotnet-install.sh --channel LTS` | Needed for `csharp-ls`. Microsoft's own script, and `LTS` is a first-class channel meaning "the most recent Long Term Support release" — so the version policy is named directly and needs no editing when .NET 11 ships. Homebrew cannot express it: there are `dotnet-sdk@8` and `@9` casks but no `@10`. Installs under `$HOME/.dotnet` with no `sudo`. |
| `typescript-language-server` | `npm i -g` | Backs the `typescript` entry in `lsp-config.json`. |
| `csharp-ls` | `dotnet tool install -g` | Backs the `csharp` entry. |
| `rust-analyzer` | `rustup component add` | Backs the `rust` entry. |

`$HOME/.cargo/bin`, `$HOME/.local/bin`, `$HOME/.dotnet` and
`$HOME/.dotnet/tools` are added to `~/.zprofile` — always, since zsh has been
the login shell since Catalina, so it is written whether or not it already
exists — and also to `~/.zshrc`, `~/.bash_profile` and `~/.profile` if those
exist. Directories outside `$HOME` are never persisted; the Homebrew prefix is
already handled by `brew shellenv`.

`DOTNET_ROOT=$HOME/.dotnet` is exported and persisted the same way, but only
when this script is the one that installed the SDK. `dotnet-install.sh` puts it
somewhere macOS does not look by default, and `csharp-ls`'s launcher can't find
its runtime without that variable.

Plugins (via the `copilot` CLI; if `copilot` is not on PATH the script prints
the exact commands and continues, since `settings.json` already enables them):

- `ponytail@ponytail` — from `DietrichGebert/ponytail`

### ⚠️ The `rtk` name collision

There are two unrelated tools called `rtk`. This setup needs
**[rtk-ai/rtk](https://github.com/rtk-ai/rtk)**, the token-optimizing proxy. The
`rtk` crate on **crates.io is a different project** — "Rust Type Kit", stuck at
0.1.0 — so `cargo install rtk` gets you the wrong one.

This matters because `rtk.json` pipes shell commands through `rtk hook copilot`.
With the wrong binary the subcommand doesn't exist. The installer installs from
git and verifies with `rtk gain`, which only the correct tool supports.

### A note on `python3`

`/usr/bin/python3` exists on a Mac with no Command Line Tools, but it is a stub
that only prompts to install them when run. So the installer *executes* python3
rather than looking for it on PATH, and Homebrew's `python` is installed if that
probe fails.

### A note on the hook files

The five Python hooks ship **CRLF**, like the rest of this package, and the
installer deliberately does *not* mark them executable: running one directly
would fail with `bad interpreter: /usr/bin/env python3^M`. Their shebang is
decoration. `copilot-hooks.json` invokes them as `python3 <path>`, which is
unaffected.

## What is deliberately NOT included

- Credentials — log in with your own account.
- Chat history, session transcripts and per-project state.
- Project memories — they are specific to someone else's codebases.

## Safety

- **Transactional copy.** Everything is staged, then swapped in, tracking what
  was replaced. If any step fails midway the previous config is restored and the
  script exits non-zero, rather than leaving `~/.copilot` half-replaced.
- **Only shipped files are touched.** The installer enumerates *files*, never
  directories, so your own instructions, prompts and skills are left alone.
- **The backup repo is created in `~/.copilot` itself**, never a parent — a
  dotfiles setup where `$HOME` is already a git repo won't get an unrelated
  commit.
- **An existing repo is never reconfigured.** If `~/.copilot` is already a git
  repo, the installer commits and nothing else: your `.gitignore` is not edited,
  and nothing is untracked. It is your repo — what it captures is your call.
  Adding an ignore rule would not untrack what is already there, but it *would*
  stop `git add` from picking up new files, so tomorrow's sessions would
  silently stop being backed up while yesterday's stayed. That check is the
  presence of `.git` in the directory itself, so it still holds when
  `~/.copilot` is a symlink into a dotfiles checkout — and on macOS, where
  `/tmp` and `/var` are themselves symlinks into `/private`.
- **A repo the installer creates gets a sensible `.gitignore`.** Setup residue,
  the bulk runtime state (`chats/`, `session-state/`, `jb/`, the logs, and both
  SQLite databases with their write-ahead logs) and `.DS_Store`.
  `session-store.db` alone runs to megabytes and its `-wal` changes on every
  interaction.

  Settings, instructions, hooks, skills and prompts are never in that list:
  those are the config, and backing them up is the point. There is no credential
  entry either — unlike `~/.claude`, `~/.copilot` has no token file, and
  `config.json` is user settings worth keeping.

## Undo

Before writing anything, the installer commits your `~/.copilot` into a local
git repo *on your machine*, so:

```bash
git -C ~/.copilot log --oneline
git -C ~/.copilot checkout <commit-before-the-backup> -- .
```

The repo is local only and never pushed.

## Partly tested on a Mac

This installer has not itself been run on macOS hardware, but most of what it
does now has been. The Claude macOS installer *has* been run end-to-end on Apple
Silicon, on a machine with no Homebrew, and the functions that carry the macOS
work are **byte-identical between the two scripts**: `install_homebrew`,
`persist_line`, `add_path`, `brew_install`, `install_dotnet` and
`have_dotnet_sdk`. So the Homebrew bootstrap, the `brew shellenv` persistence
and `dotnet-install.sh --channel LTS` are verified on hardware, and the rest of
`install_toolchain` — Node, `rustup`, `cargo` building `rtk`, `graphify`, the
language servers — differs from Claude's only in comments and warning text.

**What is still genuinely unexercised here is `brew install --cask copilot-cli`,**
and this package's own config write and hooks. That one cask line is the real
difference between the two toolchain functions. Expect that to be where anything
breaks.

What *has* been verified:

- **The whole script runs on a real bash 3.2** — the version macOS ships as
  `/bin/bash`, and what `bash setup-copilot-macos.sh` resolves to on a Mac
  without Homebrew's bash. Built from source specifically to test this rather
  than assumed from reading. It parses, installs, re-runs idempotently, rolls
  back correctly when the swap is made to fail partway, and renders `--help`.
  The one construct that genuinely differs on 3.2 — expanding an empty array
  under `set -u`, which `rollback()` does at its worst moment — was checked
  directly.
- Everything platform-neutral: the config merge, the composed
  `copilot-instructions.md`, the transactional swap and rollback, the backup
  branches and the plugin matcher are shared with the WSL installer.
- The `copilot-cli` cask exists at 1.0.80 and is a plain `binary` symlink, so it
  needs no password; `dot.net`'s `--channel LTS` and the Homebrew install script
  both resolve.

Still unexercised: the cask *install*, this package's config write and hooks on
a Mac, and the `/usr/local` branch of the Homebrew prefix loop — the Intel
layout, which the Apple Silicon run did not touch.
