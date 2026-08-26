# Permissions, backups and running remote code

The short version is in the root README under
[Before you run it](../README.md#before-you-run-it). This is the full detail.

## What gets replaced

Installing replaces your **user-level** config for the tool you install —
`~/.claude` or `~/.copilot`. Project-level config is untouched. No credentials,
chat history or project memories are included in the package; you log in with
your own account.

## The one permissive setting

- `permissions.defaultMode: "auto"` — tool calls auto-approve instead of
  prompting.

This is worth a conscious decision rather than a surprise, especially if you are
rolling this out to other people. Claude Code's own dangerous-mode warning is
left in place, so that prompt still appears. The Copilot package has no
equivalent setting.

## The deny list and the hook

A deny list and a PreToolUse hook both block reads and edits of secret-ish
files — belt and braces, so removing one does not open the other:

- **Patterns** — `.env`, `*.pem`, `*.key`, `secrets/`, `appsettings*.json`,
  `web.config`, `local.settings.json`.
- **19 rules on WSL and macOS, 21 on Windows.** The two extra: Windows also
  denies `Bash(cd *)` and `Bash(pushd *)`, for the Git Bash reason in the global
  instructions.

The deny list assumes .NET / Azure Functions projects. Skim
[`claude/windows/config/settings.json`](../claude/windows/config/settings.json)
— the WSL and macOS overlays carry the same settings — and adjust before running
if that doesn't suit you.

## There is an undo path

Your existing config is git-committed before anything is written. Each per-tool
README has the exact restore command:
[Claude](../claude/README.md#undo) · [Copilot](../copilot/README.md#undo).

## This runs remote code

It is a script from the internet piped into your shell. Read it first — `irm`
on its own prints it without running it:

```powershell
irm https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-windows.ps1
```

## Pinning to a fixed version

Two things carry a version, and **both** have to be pinned:

1. the URL you fetch the bootstrap from, and
2. `-Ref`, which decides the version of the repo the bootstrap downloads.

Pinning only the URL does **not** pin the install — the bootstrap still defaults
to `-Ref main` and would fetch the latest config. Pin both, to the same ref:

```powershell
$ref = "v1.0.0"   # a tag, branch or commit SHA
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/toperux/t4-ai-setup/$ref/install-claude-windows.ps1"))) -Ref $ref
```

Add any installer flags after `-Ref $ref`. On WSL and macOS the flag is `--ref`.
