# Claude Code setup for WSL — not implemented yet

Planned entry point: `install-claude-wsl.sh` at the repo root.

The portable config already lives in [`../shared/`](../shared) and needs no
changes — that is the whole point of the split. This directory only has to
supply what differs from Windows.

## What a WSL port needs

| Item | Work |
| --- | --- |
| `config/CLAUDE.append.md` | **Required.** The platform's shell rules, appended to `../shared/CLAUDE.core.md` at install time. May be a single line, but the file must exist — the installer fails loudly if it doesn't. Keep it **LF**, like the rest of `CLAUDE.md`. |
| `config/settings.json` | Translate the hook commands and the `statusline` command to POSIX paths. Keep the `__CLAUDE_HOME__` placeholder — the installer substitutes it. |
| statusline | `statusline-command.ps1` needs a shell equivalent. |
| `setup-claude-wsl.sh` | Port `../windows/setup-claude-windows.ps1`: same transactional stage → back up → swap → roll back shape, `apt` instead of `winget`, and the same two config roots (`--shared-source`, `--config-source`). |

Everything under `../shared/` — `RTK.md`, both Python hooks, and the graphify
skill — carries over unchanged. The hooks already branch on `os.name != "nt"`.
