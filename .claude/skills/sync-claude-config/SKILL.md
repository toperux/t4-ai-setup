---
name: sync-claude-config
description: Use when asked to sync, back-port, pull or bring changes made in the live ~/.claude config (CLAUDE.md, settings.json, agents, hooks, skills) back into this repo's claude/ sources. Detects drift by rendering the repo with the platform's installer, presents a decision menu, applies only the picked items to the repo, and verifies.
---

# sync-claude-config

Back-port edits made in `~/.claude` into `claude/`. Detect, classify, menu, apply, verify.
Repo-ahead items go the other way: take them with `update-claude-config`.

Hard rules:

- Write to the repo only. Never write to `~/.claude`.
- Re-running the installer is not a fix: it replaces `settings.json` wholesale and drops personal values.
- Stop after verify with a proposed commit message. No commit, no push.
- The repo is public. Never copy a real path, ID, user name, email or personal value into it.
- Runs on Windows (Git Bash), WSL, native Linux, macOS. It diffs the `~/.claude` of the environment it runs in.
- macOS is unverified until the first run on a Mac.

## Step 0 — preflight

- `git fetch`. Stop if the branch is behind its upstream: a stale clone makes newer repo text look like a live update.
- Warn if the working tree is dirty. The render uses the working tree.
- `git fetch` is the skill's only network call.

## Step 1 — detect

- Run `bash .claude/skills/sync-claude-config/drift.sh`.
- It renders the repo with the platform's own installer into a temp dir, matching the live opt-ins (model routing, Rust on Windows), and diffs every rendered file against `~/.claude`.
- stdout is a short summary only: platform, flags, `differs` / `MISSING` per file, candidate additions, patch path.
- Read the full diff from the printed `drift.patch` path with the Read tool. Do not rely on stdout for hunks: a shell hook compresses it.
- A non-zero exit is a real failure. Report its message; do not work around it.

## Step 2 — classify

One menu item = one logical change. It may span hunks or files. `skills/graphify/` is always one item.

**Lands in** ("current overlay" = `claude/<platform>/config` of the platform this runs on):

- Plain file → first root holding that relative path: `optional/model-routing` → current overlay → `shared`.
- `CLAUDE.md` hunk → by heading:
  - `# Model routing` onward → `optional/model-routing/CLAUDE.model-routing.md`
  - `# bash on <platform>` → the current overlay's `CLAUDE.append.md` only
  - everything else → `shared/CLAUDE.core.md`
- `settings.json` → all three overlays (windows / wsl / macos), keeping their known differences: `python` vs `python3`, statusline command, `cd`/`pushd` deny, plugin order. A change inside one of those platform lines lands in the current overlay only.
- A per-platform file (statusline script) → current overlay. Note the other two may need the same change by hand.

**Also touches**:

- Grep the repo for the old value or phrase.
- Check the places that summarise config instead of quoting it:
  - `claude/README.md` settings row and the deny-rule count
  - `claude/wsl/README.md`, `claude/macos/README.md` settings rows
  - `docs/what-it-installs.md` ("The config", "What's in the global instructions")
  - `README.md` and `docs/security.md` (permission posture)
- Docs are updated together with the change.
- Copilot counterparts (e.g. `copilot/shared/copilot-instructions.core.md`) are a note only. Apply only if explicitly picked; the Copilot core diverged on purpose.

**Direction** — settle which side is newer before recommending. Primary signal: the repo's history (current, per Step 0).

- First put the live text in repo form: the real home path back to `__CLAUDE_HOME__`. Repo history never holds a real path.
- *repo ahead* — both must hold:
  - the live text is not in the current repo file, and
  - an earlier version of the repo file had it at that spot, and a repo commit changed it (`git log -p -S'<live text>' -- <repo file>`).
  - Meaning: the live copy is an old install. Taking it would revert a repo change.
  - `-S` alone is not enough: it also matches text that merely moved or is still there.
- *live ahead* — the live text never appeared in the repo file.
- *removal* — live lacks something the repo has. Never recommend "take":
  - `~/.claude` history shows it present, then removed → your call, with the date
  - otherwise → *unknown*, most likely an install older than that repo addition
- *move* — a line present on both sides in different places. One item, not a removal. Classify it by the side that added the new structure. `git log -S` cannot see a move: the line count does not change.
- Secondary, only when `~/.claude` is a git repo:
  - Add the date of the live change ("live since MM-DD").
  - If it predates the repo file's last commit, add "passed over by `<commit>`". A hint, not a verdict.
  - A *repo ahead* item whose live text was re-added after the repo commit that dropped it is a deliberate revert → your call, not skip.
  - Never read "uncommitted in `~/.claude`" as new on its own. The installer's backup commit precedes the copy, so a fresh install looks uncommitted too.
- `skills/graphify/`: compare `.graphify_version`. Live newer → take. Live older or equal with differences → skip as repo ahead.

**Flag**:

- *personal / machine* — paths, IDs, account or project data (e.g. `remote.*`, `autoMode`, `CLAUDE_CODE_PLUGIN_DIRS`), state of plugins the repo does not ship
- *loosens a shipped default* — e.g. deny → ask
- *contradicts a documented stance* — e.g. a README states a different value
- *not shipped today* — depends on a plugin or file the repo does not install

**Recommendation**:

| Case | Rec |
|---|---|
| personal / machine | not offered — no number |
| repo ahead | skip — live copy stale |
| live ahead, no flag | take |
| live ahead with any other flag, or direction unknown | your call |
| removal, or a deliberate revert of a repo change | your call |
| shipped file deleted from `~/.claude` (`MISSING`) | your call |
| file not shipped today (candidate addition) | footer only, default skip |

Only *repo ahead* forces a skip; *personal / machine* is never offered. A "passed over" note informs, it does not decide.

Before building the menu, read `skipped.local.md` (next to this file) if it exists. Items matching an entry go to the "previously skipped" count, not the menu.

## Step 3 — menu

Post in chat:

1. Summary table `# · file · change · newer side · flag · rec` (newer side = `live`, `repo` or `removed`, from the Direction rules, with the date when known), grouped **Take → Your call → Skip**, then **Personal — not offered** as one compact unnumbered line.
   - Personal / machine items get no number and cannot be picked. They are worked out again on every run.
2. Detail bullets for each Take and Your call item: change (before → after, one or two lines), lands in, also touches. Skip items stay one line each, with the reason. Repo-ahead items show the repo's value.
3. Footer:
   - noise ignored: CRLF, `*.bak`, a `# graphify` block in live `CLAUDE.md` (the installers strip it on purpose)
   - not shipped today: one line per candidate addition, unnumbered. To ship one, name its path in the reply.
   - `previously skipped (n)`
4. Reply syntax: `1 3 5` · `recommended` · `all` (Take + Your call) · `none` · `7?` (full diff of item 7) · `skipped?` (list skip-list entries, unnumbered; naming an entry brings it back into the menu).

Use a typed reply, not the ask UI: it caps at 4 options and a run has 10-20 items.

## Step 4 — apply

- Surgical `Edit`s on repo files. Never copy a live file over (CRLF, personal values).
  - Exception: `skills/graphify/` is mirrored as a tree, minus `*.bak`. Files the newer version dropped are deleted from the repo too.
- settings: home path back to `__CLAUDE_HOME__`; same change in the windows / wsl / macos overlays.
- Update the "Also touches" docs in the same pass.
- A picked new file goes under `shared/` (or the current overlay if platform-specific), plus its rows in `claude/README.md` and `docs/what-it-installs.md`.
- Update `skipped.local.md` (gitignored, one per machine):
  - Every numbered item not taken gets one line: file, key or heading, short value summary, reason, date.
  - Personal / machine items are never written to it.
  - Drop an entry when its drift is gone, or when the live value no longer matches its summary, so a real update resurfaces.
  - It is the only memory. On later runs anything not in it is a live change, repo-ahead or personal.

## Step 5 — verify

- Re-run `drift.sh`: taken items are gone, skipped ones remain, nothing new appeared.
- All three `settings.json` parse: `jq empty <file>`; without `jq`, `python -m json.tool <file>` on Windows and `python3 -m json.tool <file>` elsewhere (on Windows only `python` is guaranteed; `python3` can be the Store stub).
- `wsl` and `macos` `settings.json` are identical; windows vs wsl differs only on the known platform lines.
- No `\r` (count with `tr -cd '\r' < file | wc -c`, never `grep`: Git Bash's `grep` strips CR and reports 0 for a fully CRLF file), no home path, user name or email, and no value from a personal item. Check `git diff` and untracked files (`git ls-files --others --exclude-standard`); `git diff` alone misses new files.
- Show `git diff --stat` and a proposed commit message in the repo's style (imperative, sentence case, no prefix). Stop.
