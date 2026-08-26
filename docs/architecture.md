# How the repository is put together

Contributor-facing notes. Nothing here is needed to install anything — see the
[root README](../README.md) for that.

## Repository layout

```
.gitattributes                 `* -text` — config files ship byte for byte
.gitignore
install-claude-windows.ps1     entry point, downloads this repo and runs the installer
install-claude-wsl.sh
install-claude-macos.sh
install-copilot-windows.ps1
install-copilot-wsl.sh
install-copilot-macos.sh
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
copilot/                       same shape, same three platforms
```

## Why the bootstraps download different archive formats

The Windows bootstrap downloads a zip; the WSL and macOS ones download a
tarball, because `tar` is everywhere while `unzip` often isn't — and unlike the
zip, the tarball preserves the executable bit.

## Shared tree plus a per-platform overlay

Config is split into a platform-neutral `shared/` tree and a per-platform
overlay, and the installer merges the two with the overlay winning. That keeps
the portable ~85% of the config in one place rather than triplicated across the
three platforms.

## The global instructions are composed at install time

The one file that is neither fully portable nor fully platform-specific — the
global instructions — is **composed at install time** from
`shared/CLAUDE.core.md` plus `windows/config/CLAUDE.append.md`. The two halves
are a byte cut of the original file, joined byte for byte, so what lands in
`~/.claude/CLAUDE.md` is exactly the original.

Each per-tool README explains the cut for its own platform — see
[Why CLAUDE.md is split](../claude/README.md#why-claudemd-is-split).
