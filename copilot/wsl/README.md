# GitHub Copilot CLI user setup for WSL

A copy of a working Copilot CLI user-level setup: global instructions, settings,
LSP config and five hooks — plus the command-line tools those settings depend
on. Everything lands in `~/.copilot` **inside the WSL distro**, not the Windows
one. No credentials, chat history or project memories are included; you log in
with your own account.

WSL port of [`../windows/setup-copilot-windows.ps1`](../windows). Everything
platform-neutral is shared with it and with the macOS port — see
[`../shared/`](../shared).

## Prerequisites

- A WSL 2 distro with `sudo` rights (apt, dnf, pacman and zypper are all
  handled; apt is what this was built against)
- `curl` and `python3` — the script installs both if your distro's package
  manager has them, but `python3` must be present for the config step

The Copilot CLI itself is installed for you.

## Run it

```bash
curl -fsSL https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-copilot-wsl.sh | bash
```

Or, from a checkout of this repo:

```bash
bash copilot/wsl/setup-copilot-wsl.sh
```

Idempotent — safe to re-run. Anything already installed is skipped.

Flags (to pass these through the one-liner, see the
[root README](../../README.md#passing-flags)):

| Flag | Effect |
| --- | --- |
| `--skip-toolchain` | Only copy the config; install no tools. |
| `--skip-plugins` | Skip the `copilot plugin` installs. |
| `--skip-backup` | Don't git-commit `~/.copilot` first. Overwrites with no undo path. Only needed if you're running `--skip-toolchain` on a machine without git. |
| `--copilot-dir <path>` | Write the config somewhere other than `~/.copilot`. |
| `--shared-source <path>` | The platform-neutral config tree (default `../shared`). |
| `--config-source <path>` | The platform overlay (default `./config`). |

## What's in the package

Config is split in two: `shared/` holds everything identical on every platform,
`wsl/config/` holds only what is WSL-specific. The installer merges them, with
the overlay winning on a collision.

| File | What it does |
| --- | --- |
| `shared/copilot-instructions.core.md` + `wsl/config/copilot-instructions.append.md` | Global instructions loaded into every session: think before coding, simplicity first, surgical changes, goal-driven execution. Plus a terse-reporting preference and a WSL note about keeping working copies off `/mnt/c` and converting paths with `wslpath -w`. **Composed into `~/.copilot/copilot-instructions.md` at install time.** |
| `shared/settings.json` | Model `gpt-5.6-terra`, `effortLevel: high`, startup tips off, and a footer showing model effort, directory, branch, context window, quota, agent and sandbox. Enables the `ponytail@ponytail` plugin and registers its marketplace. No paths, no shell — portable as-is. |
| `shared/lsp-config.json` | Language servers for TypeScript/JS, C# and Rust, by bare command name. |
| `shared/hooks/check_sensitive_files.py` | PreToolUse on Read/Edit/Write. Blocks secret-ish files — `.env`, `*.pem`, `*.key`, `secrets/`, `appsettings*.json`, `web.config`, `local.settings.json`. |
| `shared/hooks/command_policy.py` | PreToolUse on Bash. Blocks `git push` and bare `cd`. |
| `shared/hooks/worktree_guard.py` | PreToolUse on Bash. Denies `git worktree add` outside the allowed roots. |
| `shared/hooks/graphify_hint.py` | PreToolUse on Bash/Grep/Glob. Suggests `graphify query` before a text search. |
| `shared/hooks/graphify_update_notice.py` | PostToolUse on Edit/Write. Reminds you to run `graphify update .`. |
| `shared/intellij-skills/debug/` | The `debug` skill. |
| `wsl/config/hooks/copilot-hooks.json` | Registers the five hooks above. WSL-specific: every entry is keyed on `"bash"` and calls `python3 "$HOME/.copilot/hooks/…"`. |
| `wsl/config/hooks/rtk.json` | Routes shell commands through `rtk hook copilot`, also keyed on `"bash"`. |
| `wsl/setup-copilot-wsl.sh` | The installer. |

### Why the two hook files use different naming

`copilot-hooks.json` keys its events `PreToolUse`/`PostToolUse` and matches
`Read|Edit|Write`; `rtk.json` keys its event `preToolUse` and matches
`bash|powershell`. Both are correct and the difference is deliberate. Copilot
accepts two conventions: **PascalCase** events take Claude-format matchers
(`Bash`, `Read`, `Edit`), **camelCase** events take runtime tool names (`bash`,
`view`, `edit`). Matching is case-sensitive and the matcher vocabulary follows
the event's convention — so pairing a camelCase event with `Read|Edit|Write`,
or a PascalCase one with `bash`, silently stops the hook firing. Carried over
from the Windows overlay unchanged, and asserted by the test suite.

### Why copilot-instructions.md is split

Everything in it is platform-neutral except the closing `# bash on …` section,
so the file is cut at that heading and the installer joins the two halves
**byte for byte**. The cut is a byte offset of the original, so `core + append`
reproduces it exactly: no re-encoding, no line-ending changes. This file is
**CRLF throughout** (the Claude one is LF), and the appendix here is CRLF to
match — the installer checks the result and warns if a bare LF appears.

Both halves are required. If the platform overlay has no
`copilot-instructions.append.md`, the installer stops rather than shipping
instructions that are missing a rule.

## What the installer installs

Each is skipped if already on PATH. Nothing you already have is upgraded.

| Tool | Via | Why |
| --- | --- | --- |
| `copilot` | `curl -fsSL https://gh.io/copilot-install \| bash` | The Copilot CLI. GitHub's own installer rather than `npm i -g @github/copilot`: it is a single static binary with no Node requirement, and as a normal user it lands in `$HOME/.local/bin` with no `sudo`. You still log in with your own account. |
| `rtk` | `cargo install --git https://github.com/rtk-ai/rtk --locked` | **Required.** A hook routes shell commands through `rtk hook copilot`. From **git, not crates.io** — see the warning below. |
| `graphify` | `uv tool install graphifyy` | Backs the two graphify hooks. The PyPI package really is spelled with two y's. |
| `git`, `python3`, `jq`, `curl` | distro package manager | Backup step, the five hooks, JSON wrangling. |
| `uv` | `astral.sh/uv/install.sh` | Installs graphify. |
| `rustup` | `sh.rustup.rs` | Provides `cargo` (for `rtk`) and `rust-analyzer`. |
| Node.js | distro, or an existing `nvm` | Needed for the TypeScript language server. An `nvm`-managed Node is detected and used rather than installing a second one. |
| .NET SDK | `dotnet-sdk-10.0`, falling back to `8.0` | Needed for `csharp-ls`. LTS only — 9.0 is skipped deliberately, since it is STS. |
| `typescript-language-server` | `npm i -g` | Backs the `typescript` entry in `lsp-config.json`. |
| `csharp-ls` | `dotnet tool install -g` | Backs the `csharp` entry. |
| `rust-analyzer` | `rustup component add` | Backs the `rust` entry. |

`$HOME/.cargo/bin`, `$HOME/.local/bin`, the npm prefix and
`$HOME/.dotnet/tools` are appended to `~/.profile`, `~/.bashrc` and `~/.zshrc`
where those exist. Directories outside `$HOME` are never persisted — on
Debian/Ubuntu the npm prefix is `/usr`, and writing that into every rc file is
pure noise.

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
git and verifies with `rtk gain`, which only the correct tool supports. If you
already have the crates.io `rtk`, it is replaced (with a warning).

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
  `~/.copilot` is a symlink into a dotfiles checkout.
- **A repo the installer creates gets a sensible `.gitignore`.** Setup residue
  plus the bulk runtime state: `chats/`, `session-state/`, `jb/`, the logs, and
  the two SQLite databases with their write-ahead logs. `session-store.db` alone
  runs to megabytes and its `-wal` changes on every interaction.

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

## Test coverage

64 assertions across this installer and the macOS one, run on a real WSL bash
against the shipped script text: the composed instructions file (byte-identical
to `core + append`, and pure CRLF), the retargeted hook config, an idempotent
re-run, a config filename containing a space, the missing-overlay hard stop,
files the package doesn't ship surviving, both backup branches including an
existing repo reached through a symlink, and the macOS platform guard.

The Homebrew, cask and `dotnet-install.sh` paths belong to the macOS port and
are unexercised — see [`../macos/README.md`](../macos/README.md).
