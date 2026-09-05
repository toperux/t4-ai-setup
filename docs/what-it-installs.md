# What each installer installs

Config, plus the command-line tools that config depends on. The
[root README](../README.md#install) has the install commands.

## The config

- **Claude Code** — writes 16 files into `~/.claude`: instructions, settings,
  two Python hooks, a statusline, the graphify skill.
- **Copilot CLI** — writes 10 files into `~/.copilot`: instructions, settings,
  LSP config, five Python hooks, hook registrations.

Neither installer upgrades a tool you already have; version policy only applies
when a command is missing. Both git-commit your existing `~/.claude` /
`~/.copilot` into a local repo before writing anything, so there is an undo
path — see [Permissions, backups and running remote code](security.md).

File-by-file detail lives in the per-tool READMEs:
[Claude](../claude/README.md#whats-in-the-package) ·
[Copilot](../copilot/README.md#whats-in-the-package).

## The tools

Each one is probed on PATH first and skipped if it is already there. Sources
differ by platform — winget plus the official Node MSI on Windows,
apt/dnf/pacman/zypper plus `rustup` and `uv` on WSL, Homebrew on macOS.

| Tool | Why | Claude | Copilot |
| --- | --- | :-: | :-: |
| `rtk` | **Required** — a hook routes every shell command through it | ✅ | ✅ |
| `graphify` | Backs the graphify skill and the graphify hooks | ✅ | ✅ |
| The CLI itself | `claude` or `copilot`, only when missing | ✅ | ✅ |
| Homebrew | macOS only — everything else depends on it | macOS | macOS |
| `git` | The config backup, and Claude's statusline branch | ✅ | ✅ |
| Python | Runs the hooks — two for Claude, five for Copilot | ✅ | ✅ |
| `jq` | JSON wrangling (plus `curl` on WSL) | ✅ | ✅ |
| Node.js LTS | Only to provide `typescript-language-server` | ✅ | ✅ |
| .NET SDK (LTS) | Only to provide `csharp-ls` | ✅ | ✅ |
| `rustup` | Only to provide `rust-analyzer` — and `cargo` off Windows | ✅ | ✅ |
| `typescript-language-server`, `csharp-ls`, `rust-analyzer` | The servers the LSP plugins and `lsp-config.json` drive | ✅ | ✅ |

**Notes**

- **`rtk` is rtk-ai/rtk, not the unrelated crates.io crate of the same name.**
  It is a token-optimizing CLI proxy that claims 60–90% savings on dev
  operations. Windows takes a prebuilt binary from winget (`rtk-ai.rtk`), no
  Rust needed; WSL and macOS still build it with `cargo`. If the wrong `rtk`
  wins on PATH every shell call fails — the per-tool READMEs have a section on
  the collision: [Claude](../claude/README.md) · [Copilot](../copilot/README.md).
- **The graphify PyPI package is spelled `graphifyy`**, with two y's.
- **The CLI comes from its own vendor's installer** — user-scope, no elevation.
  Copilot comes from winget on Windows, `gh.io/copilot-install` on WSL and the
  `copilot-cli` cask on macOS. Only when missing, so an existing install is
  never upgraded and a running one is never replaced. You still log in yourself.
- **Homebrew's `brew shellenv` is persisted to your profile**, which Homebrew's
  own installer only prints as an instruction.
- **Python**: Windows installs 3.14; macOS installs Homebrew's, probed by
  *running* `python3` since `/usr/bin/python3` is a stub on a Mac with no
  Command Line Tools. **On WSL `python3` must already exist** — the installer
  stops early if it doesn't.
- **The .NET LTS major is resolved at run time** on Windows and WSL; macOS uses
  Microsoft's `dotnet-install.sh --channel LTS`, which names the policy
  directly.

## Rust is opt-in on Windows only

| | Windows | WSL | macOS |
| --- | :-: | :-: | :-: |
| Rust installed by default | — | ✅ | ✅ |

A default Windows install downloads nothing from `static.rust-lang.org`, because
nothing there needs a toolchain — `rtk` arrives as a prebuilt binary. That
matters because corporate web filters have been seen to block rustup's ~200 MB
of downloads outright, reporting them as a trojan.

Pass `-WithRust` to get the toolchain, `rust-analyzer` and the Rust LSP wiring
back:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-windows.ps1))) -WithRust
```

The flag decides the config too, so what is installed and what is configured
cannot disagree: without it, `rust-analyzer-lsp` is dropped from
`enabledPlugins` and the `rust` entry from `lsp-config.json`. Full detail:
[claude/README.md](../claude/README.md#rust-is-opt-in) ·
[copilot/README.md](../copilot/README.md#rust-is-opt-in).

WSL and macOS still install Rust, because `cargo` is how `rtk` is built there.

## What's in the global instructions

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
`wslpath` on WSL, the BSD userland and bash 3.2 on macOS. How the two halves
are joined is in
[architecture.md](architecture.md#the-global-instructions-are-composed-at-install-time).

## Skills

- **`graphify`** (Claude) — turns a codebase into a persistent, queryable
  knowledge graph and answers architecture and file-relationship questions from
  it instead of grepping. Shipped as a snapshot, then refreshed from your
  installed `graphify` so the two versions match.

## Plugins

Enabled in `settings.json` and installed from `anthropics/claude-plugins-official`
and `DietrichGebert/ponytail` — Copilot uses only the latter:

| Plugin | What it does | Claude | Copilot |
| --- | --- | :-: | :-: |
| `ponytail` | Forces the laziest solution that works — YAGNI, stdlib first | ✅ | ✅ |
| `typescript-lsp` | TypeScript/JavaScript code intelligence | ✅ | — |
| `csharp-lsp` | C# code intelligence | ✅ | — |
| `rust-analyzer-lsp` | Rust code intelligence | ✅ | — |

Copilot gets the same three language servers through `lsp-config.json` rather
than through plugins. Pass `-SkipPlugins` / `--skip-plugins` to skip this step
entirely; the settings still enable them, so a first session would fetch them.
