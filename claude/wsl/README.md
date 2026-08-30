# Claude Code user setup — WSL

A copy of a working Claude Code user-level setup: global instructions, settings,
hooks, a statusline and one skill — plus the command-line tools those settings
depend on. Everything lands in `~/.claude` inside your WSL distro. No
credentials, chat history or project memories are included; you log in with your
own account.

Tested on Ubuntu 24.04 under WSL2. The script is distro-agnostic (apt, dnf,
pacman and zypper are all handled), but only apt has been exercised.

## Prerequisites

- A WSL distro with `sudo` rights, `curl` and `tar`.
- **`python3`** — required, not optional. It renders `settings.json`, strips the
  graphify block and validates the result, and both hooks run under it. The
  installer stops early with a clear message if it is missing.
- Nothing else. Claude Code itself is installed if it's missing; you log in with
  your own account.

## Run it

```bash
curl -fsSL https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-wsl.sh | bash
```

Flags pass straight through after `-s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-wsl.sh | bash -s -- --skip-toolchain
```

Or, from a checkout of this repo:

```bash
bash claude/wsl/setup-claude-wsl.sh
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
platform, `wsl/config/` holds only what differs. The installer merges them, with
the overlay winning on a collision.

| File | What it does |
| --- | --- |
| `shared/CLAUDE.core.md` + `wsl/config/CLAUDE.append.md` | Global instructions loaded into every session: think before coding, simplicity first, surgical changes, goal-driven execution. Plus a terse-reporting preference and a WSL note about `/mnt/c` performance and `wslpath`. **Composed into `~/.claude/CLAUDE.md` at install time** — see below. |
| `wsl/config/settings.json` | Model `opus`, `effortLevel: high`, dark fullscreen TUI, autocompact at 60% of the context window. Deny-rules covering `.env`, `*.pem`, `*.key`, `secrets/`, `appsettings*.json`, `web.config`, `local.settings.json`, plus `git push`. Wires up the hooks and statusline below, and enables the four plugins. |
| `shared/hooks/check_sensitive_files.py` | PreToolUse hook. Hard-blocks Read/Edit/Write on secret-ish files (exits 2), independent of the deny-rules — belt and braces. |
| `shared/hooks/worktree_guard.py` | PreToolUse hook on Bash. Denies `git worktree add` outside the allowed roots, so worktrees stop landing in the workspace root. |
| `wsl/config/statusline-command.sh` | Statusline: ponytail marker, reasoning effort, then capsule pills for model/context, 5-hour and 7-day rate limits, followed by account email and current git branch. Needs `python3`. |
| `shared/skills/graphify/` | The `graphify` skill — builds a queryable knowledge graph of a codebase — with its reference docs. Shipped as a snapshot, then refreshed by `graphify install --platform claude` so it matches the version actually installed. |
| `shared/RTK.md` | How `rtk` (the token-optimizing CLI proxy) works and its meta commands. |
| `wsl/setup-claude-wsl.sh` | The installer. |

### Why CLAUDE.md is split

Everything in it is platform-neutral except the closing shell section. Shipping
the whole file per platform would triplicate the other ~70 lines across Windows,
WSL and macOS, and they would drift apart. So the file is cut at that heading —
`shared/CLAUDE.core.md` plus `wsl/config/CLAUDE.append.md` — and the installer
joins the two with `cat`, byte for byte.

Both halves are required. If the overlay has no `CLAUDE.append.md`, the
installer stops rather than shipping instructions that are missing a rule.

## How this differs from the Windows package

Same 16 files, same behaviour. Four deliberate deltas:

| | Windows | WSL |
| --- | --- | --- |
| Hook interpreter | `python` | `python3` |
| Statusline | `statusline-command.ps1` via PowerShell | `statusline-command.sh` via bash |
| `Bash(cd *)` / `Bash(pushd *)` deny-rules | present | **absent** — they exist because Git Bash on Windows makes the final cwd unstatic, which is not true here |
| Package manager | `winget` + the official Node MSI | `apt`/`dnf`/`pacman`/`zypper`, `rustup`, `uv` |

## What the installer installs

Each is skipped if already on PATH:

| Tool | Via | Why |
| --- | --- | --- |
| `rtk` | `cargo install --git https://github.com/rtk-ai/rtk --locked` | **Required.** A hook routes every Bash tool call through `rtk hook claude`. From **git, not crates.io** — see the warning below. |
| `graphify` | `uv tool install graphifyy` | Backs the bundled skill and its two hooks. The PyPI package really is spelled with two y's. |
| `claude` | `curl -fsSL https://claude.ai/install.sh \| bash` | Claude Code itself. Anthropic's own installer: user scope, checksum-verified, lands in `~/.local/bin`, and refuses to run under `sudo`. Only when missing — an existing install is never upgraded, and a running one is never replaced, because a running one isn't missing. |
| `git`, `jq`, `curl`, `python3` | distro package manager | Backup step, JSON wrangling, hooks. |
| `rustup` | `sh.rustup.rs` | Provides `cargo` (for `rtk`) and `rust-analyzer`. |
| `uv` | `astral.sh/uv/install.sh` | Installs graphify. |
| Node | distro, or an existing `nvm` | Needed for the TypeScript language server. The installer warns if the resulting Node is older than 18. |
| .NET SDK | `dotnet-sdk-10.0`, falling back to `8.0` | Needed for `csharp-ls`. Both are LTS; 9.0 is skipped deliberately as STS. |
| `typescript-language-server` | `npm i -g` | Behind the `typescript-lsp` plugin. |
| `csharp-ls` | `dotnet tool install -g` | Behind the `csharp-lsp` plugin. |
| `rust-analyzer` | `rustup component add` | Behind the `rust-analyzer-lsp` plugin. |

`$HOME/.cargo/bin`, `$HOME/.local/bin` and `$HOME/.dotnet/tools` are appended to
`~/.profile`, `~/.bashrc` and `~/.zshrc` if they exist and don't already have
them. Directories outside `$HOME` are never persisted — on Debian/Ubuntu
`npm config get prefix` is `/usr`, and writing that into every rc file is pure
pollution.

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
  That check is the presence of `.git` in the directory itself, so it still
  holds when `~/.claude` is a symlink into a dotfiles checkout.
- **A repo the installer creates gets a sensible `.gitignore`.** Credentials,
  setup residue, and bulk runtime state (`projects/`, `file-history/`,
  `history.jsonl`, `plugins/`, the caches) are excluded from the start, so a
  fresh machine never starts committing megabytes of session data that is no
  use as an undo point.

### Why an existing repo is left alone

Adding `projects/` to a `.gitignore` does not untrack the session files already
in the repo, but it *does* stop `git add` from picking up new ones. Tomorrow's
sessions would silently stop being backed up while yesterday's stayed — worse
than either choice made outright, and it would quietly break anyone using this
repo to restore sessions.

The installer only warns about one thing: if the repo tracks
`.credentials.json`, it says so, because those are live OAuth tokens. It does
not act. To stop committing them:

```bash
git -C ~/.claude rm --cached .credentials.json
```

## Undo

Before writing anything, the installer commits your `~/.claude` into a local git
repo, so:

```bash
git -C ~/.claude log --oneline
git -C ~/.claude checkout <commit-before-the-backup> -- .
```

The repo is local only and never pushed.
