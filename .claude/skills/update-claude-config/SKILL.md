---
name: update-claude-config
description: Brings what is new in this repo's claude/ sources into the live ~/.claude config (repo -> live ~/.claude); use when asked to update, refresh or pull the local user-level Claude config (CLAUDE.md, settings.json, agents, hooks, skills) from this repo without re-running the installer. Reuses sync-claude-config's drift detection, presents a decision menu, applies only the picked items to ~/.claude with a backup, keeps everything personal, and verifies.
---

# update-claude-config

Take repo changes in `claude/` into `~/.claude`. The mirror of `sync-claude-config`. Preflight, detect, classify, menu, apply, verify.

Hard rules:

- Write to `~/.claude` only. Never to the repo, apart from this skill's own `skipped.local.md`.
- Never run the installer against `~/.claude`: it replaces `settings.json` and `CLAUDE.md` wholesale and drops personal values and live edits.
- Install nothing: no tools, no plugins. Name the install command instead.
- Never number, apply or overwrite a personal / machine value.
- Runs on Windows (Git Bash), WSL, native Linux, macOS. It updates the `~/.claude` of the environment it runs in.

## Step 0 — preflight

- `git fetch`.
- Behind upstream, clean tree, no local commits → `git pull --ff-only`, say so, continue. "New in the repo" then means the latest.
- Behind and it cannot fast-forward (local commits or uncommitted changes) → stop. Never merge, rebase or stash.
- Warn and ask before continuing (a question, not a stop) when the render would carry text that is not on the published default branch:
  - the tree is dirty, or the branch is ahead of its upstream
  - the checkout is not the default branch (`origin/HEAD`), has no upstream, or is a detached HEAD
- Record `git rev-parse HEAD` and `git status --porcelain` now, after any pull. Steps 4 and 5 compare against them.

## Step 1 — detect

- Run `bash .claude/skills/sync-claude-config/drift.sh`. Read the summary, and `drift.patch` from the printed path with the Read tool.
- Record a `cksum` of the patch **and** of the summary text. Step 4 uses both; `MISSING` files are in the summary, not the patch.
- In the patch, `-` lines are the repo's rendered version and `+` lines the live version. Applying an item makes the live side equal the `-` side.
- The render dir (`render/` next to the patch) holds every shipped file as the installer would write it, real home path included. It is the source for everything applied.
- Files the repo dropped: `drift.sh` cannot see them. List them from history, strip the root prefix, keep those that still exist in `~/.claude` and are not in the render:
  `git log --no-renames --diff-filter=D --name-only --format= -- claude/shared claude/<folder>/config claude/optional/model-routing`
  - `<folder>` is the repo folder, not `drift.sh`'s platform label: Windows → `windows`, Linux and WSL → `wsl`, macOS → `macos`. `claude/linux/` does not exist and would match nothing without an error.

## Step 2 — classify

One menu item = one logical change. It may span hunks or files. `skills/graphify/` is always one item.

**Direction** — read the "Direction" section of `.claude/skills/sync-claude-config/SKILL.md` and apply it as written. Here the outcomes map to the opposite recommendation:

| Outcome | Meaning here | Rec |
|---|---|---|
| *repo ahead* | the repo changed this, live still has the old version | take |
| `MISSING` file | the repo ships a file the live config lacks | take |
| *removal*, live history shows you removed it | deliberate | yours |
| *removal*, the live file was last modified **before** the repo commit that added the line | nobody removed it; the file predates the addition | take |
| *removal*, anything else | cannot tell a stale install from a deliberate deletion | your call |
| *live ahead* | your own edit, not in the repo yet | yours — belongs to `sync-claude-config` |
| deliberate revert | you re-added text after the repo dropped it | yours |
| live file the repo used to ship (Step 1's deletion list) | the repo dropped it | your call |
| live-only file the repo never shipped | yours | footer only |

- The removal rows are cautious on purpose: "take" for an unexplained removal would quietly undo a deletion on any machine without `~/.claude` history.
- Removal comparison, exactly:
  - repo side: the **first** commit that added the line, by **author** date — `git log --reverse --format=%at -S'<line>' -- <repo file> | head -1`. Not the newest match (a line can be dropped and re-added), not the committer date (a rebase moves it).
  - Search the stable part of the line, so a later cosmetic change is not mistaken for the addition. In `settings.json`: the key alone (`"X":`), no value punctuation, no trailing comma.
  - live side: the file's mtime in epoch seconds — `stat -c %Y` (Linux, Git Bash) or `stat -f %m` (macOS).
  - Claude Code rewrites `settings.json` itself. That only makes the file look newer and pushes items to "your call", the safe direction.
  - If that first commit replaced another line at the same spot, it is a reword, not an addition → your call.
- **Move** — a line present on both sides in different places is a move, not a removal. One item, classified by the side that added the new structure (e.g. a rule moved from `deny` into a live-only `ask` block → live ahead → yours). `git log -S` cannot see a move: the line count does not change. A missed move would number a personal item.

**Flag** — can turn a "take" into "your call" or "skip":

- *personal / machine* — paths, IDs, account or project data (e.g. `remote.*`, `autoMode`, `CLAUDE_CODE_PLUGIN_DIRS`), state of plugins the repo does not ship → yours, never touched
- *state Claude Code writes itself* — e.g. `skipDangerousModePermissionPrompt` after you accepted that prompt → skip
- *changes the permission or safety posture* — deny / ask / allow rules, `defaultMode`, hooks added or removed → your call
- *needs something the installer would have installed* — a hook or setting that calls a tool, or enables a plugin, not present on this machine (`command -v`, `claude plugin list`) → your call, with the install command
- `skills/graphify/` — owned by `graphify install`, which writes the installed CLI's skill, not the repo snapshot. A snapshot that differs from the CLI makes graphify warn on every call. Compare the repo's `.graphify_version` (bare version, no newline) with `graphify --version 2>/dev/null | awk '{print $2}' | tr -d '\r'` (the CLI prints `graphify <version>`, with a CR on Windows and a warning on stderr):
  - CLI installed and versions differ → skip. Name the fix: `uv tool upgrade graphifyy`, then `graphify install --platform claude`.
  - versions match, or no CLI installed (the installer itself then leaves the snapshot) → your call.

Before building the menu, read `skipped.local.md` (next to this file) if it exists. Numbered items matching an entry go to the "previously skipped" count, not the menu.

**How each item is applied** — decided per file **after** the reply, never before:

- *whole file* — only if every hunk of that file in `drift.patch` is picked. Previously skipped hunks and unnumbered "Yours" hunks count as not picked, so a file holding anything of yours is never copied over.
- *hunk* — otherwise: surgical `Edit` of just the picked hunks. Typical for `settings.json` and `CLAUDE.md` on a customised machine.
- `skills/graphify/` — the directory is replaced as a whole, so files the snapshot no longer has do not linger.

## Step 3 — menu

Same layout and reply syntax as `sync-claude-config`:

- Only items safe to apply get a number. Unnumbered **Yours — not offered** = personal / machine, live ahead, deliberate removal, deliberate revert. No reply can pick them.
- Numbered **Skip** = a repo-ahead item a flag turned into skip (state Claude Code writes itself, graphify version mismatch).
- `all` = Take + Your call. A Skip item is applied only when its number is named.

Post in chat:

1. Summary table `# · file · change · newer side · flag · rec`, grouped **Take → Your call → Skip**, then **Yours** as one compact unnumbered line.
2. Detail bullets for each Take and Your call item: change (live now → repo version, one or two lines) and what it needs (tool, plugin, restart). Skip items one line each, with the reason. Whole file vs hunk is not shown; it depends on the reply and is reported at apply time.
3. Footer: noise ignored (CRLF, `*.bak`), live-only files left alone (candidate additions from `drift.sh`), `previously skipped (n)`.
4. Reply syntax: `1 3 5` · `recommended` · `all` · `none` · `7?` (full diff of item 7) · `skipped?` (list skip-list entries, unnumbered) · `yours?` (expand the Yours line).

## Step 4 — apply

0. **Re-check.** Run `drift.sh` again right before applying. Stop if the patch or summary checksum differs from Step 1, or the repo's `HEAD` or `git status --porcelain` differs from Step 0. The render dir is shared and wiped on every run, so another session, or a live edit made while the menu sat, would otherwise change what gets copied.
1. **Back up first.** Copy every live file about to change to `~/.claude-config-backups/<timestamp>/<relative path>`. Print that path.
   - Outside `~/.claude` on purpose: Claude Code rotates its own files in `~/.claude/backups/`, and a `~/.claude` repo may not ignore that folder.
   - No commit in `~/.claude`: it is the user's repo and their snapshot habit. Backups are never cleaned up automatically.
2. **Whole-file items** — copy from the render dir with `cp -p`, so hook scripts stay executable on Linux and macOS. Create missing parent dirs.
3. **Hunk items** — `Edit` the live file so the change matches the patch's `-` side. The render already carries the real home path; nothing is re-templated.
   - `settings.json`: apply the key-level change, not the literal hunk. One hunk can mix a taken line with personal ones, and commas differ at the edges.
4. **Dropped files** — move the live file into the backup dir instead of deleting it.
5. **Line endings** — a live file keeps its style. A whole-file copy brings the repo's LF, as the installer would. When that turns a CRLF file into LF, say so before writing: `git -C ~/.claude diff` will show every line as changed.
   - Unconfirmed until the first real apply: a multi-line `Edit` in a CRLF live file. Step 5's mixed-ending check catches a bad result; the fallback is one `Edit` per line.
6. **Permission prompts** — these files are outside the project, so expect a prompt per file. That is intended; do not work around it.
7. **Skip list** — `skipped.local.md` next to this file (gitignored): one line per **numbered** item not taken (file, key or heading, short value summary, reason, date). Drop an entry when its drift is gone or the repo value changes again.
   - Unnumbered **Yours** items are never written to it. They are worked out again on every run.
   - `skipped?` lists entries without numbers. Naming an entry brings it back into the menu, where the normal rules classify it.

## Step 5 — verify

- Re-run `drift.sh`: taken items are gone, everything else is unchanged, nothing new appeared.
- `settings.json` parses: `jq empty <file>`; without `jq`, `python -m json.tool <file>` on Windows and `python3 -m json.tool <file>` elsewhere. On Windows only `python` is guaranteed by the installer; `python3` can be the Store stub, which would report a false failure.
- No mixed line endings in any file touched: the CR count is 0 or equal to the line count.
  - Count with `tr -cd '\r' < file | wc -c` against `wc -l < file`. **Never with `grep`**: Git Bash's `grep` strips CR and reports 0 for a fully CRLF file.
- Hook scripts and the statusline script are still executable (Linux, macOS).
- The repo is untouched: `git rev-parse HEAD` and `git status --porcelain` equal Step 0's values. The skip list is ignored, so it does not show.
- If `~/.claude` is a git repo, show `git -C ~/.claude diff --stat` for the touched files.
- Report: what changed, the backup path, and that open Claude Code sessions need a restart to pick up `CLAUDE.md` and settings changes.
- One-line undo: copy the backup back.

## Platforms

- Windows (Git Bash), WSL, native Linux, macOS — whatever `drift.sh` supports, since it does the platform work.
- Verified: detection, menu and apply on Windows (a whole-file copy and a one-line hunk edit); detection on Linux inside WSL.
- Not verified: applying on Linux (needs a Claude Code session inside WSL) and anything on macOS.
