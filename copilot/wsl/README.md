# Copilot CLI setup for WSL — not implemented yet

Planned entry point: `install-copilot-wsl.sh` at the repo root.

The portable config already lives in [`../shared/`](../shared) and needs no
changes — that is the whole point of the split. This directory only has to
supply what differs from Windows.

## What a WSL port needs

| Item | Work |
| --- | --- |
| `config/copilot-instructions.append.md` | **Required.** The platform's shell rules, appended to `../shared/copilot-instructions.core.md` at install time. May be a single line, but the file must exist — the installer fails loudly if it doesn't. Keep it **CRLF**, like the rest of `copilot-instructions.md`. |
| `config/hooks/copilot-hooks.json` | The Windows copy keys every hook on `"powershell"` and uses `$env:USERPROFILE\...` paths. Both need the shell equivalent. |
| `config/hooks/rtk.json` | Same — `"powershell": "rtk hook copilot"` needs the shell key. |
| `setup-copilot-wsl.sh` | Port `../windows/setup-copilot-windows.ps1`: same transactional stage → back up → swap → roll back shape, `apt` instead of `winget`, and the same two config roots (`--shared-source`, `--config-source`). |

Everything under `../shared/` — `settings.json`, `lsp-config.json`, all five
Python hooks, and `intellij-skills/` — carries over unchanged. `settings.json`
and `lsp-config.json` contain no paths and no shell, and the hooks already
branch on `os.name != "nt"`.
