
# Model routing

Prices ($/M tokens, in/out): Fable 5.1 10/50 · Opus 5.5 4/20 · Sonnet 5 2/10 · Haiku 4.5 1/5 (200K ctx).

| Work | Who | Model | Effort |
|---|---|---|---|
| Orchestration, plan mode, spec refinement, review of subagent diffs, smoke-test triage | main session | Fable | set via `/effort` |
| Implementing a planned change, writing tests | `coder` agent | Opus | high |
| Running gates / tests, reporting output | `tester` agent | Sonnet | low |
| Searches, lookups, file inventories | `finder` agent | Haiku | n/a (Haiku 4.5 has no effort) |
| Doc edits, writing one-off scripts, big-file reads | `scribe` agent | Sonnet | low |

Rules:

- Agent defs in `~/.claude/agents/` carry model + effort — use `subagent_type: "coder" | "tester" | "finder" | "scribe"` and don't re-pass `model` unless overriding. A project can override any of them with a same-named def in its own `.claude/agents/`.
- Built-in agent types (`Explore`, `Plan`, `general-purpose`, `claude`, `claude-code-guide`) aren't pinned by these defs and can resolve to the main session model (Fable). Prefer the defs above; if a built-in is needed, always pass `model:` explicitly.
- Never use `subagent_type: "fork"` for coding work — fork ignores `model` and runs on the main session model.
- Small edits (one file, ≤20 lines) the main session does directly; spawning an agent costs more than the edit.
- Delegate when work is parallel, long-running, or would flood main context.
- The main session's own model comes from `/model`, not this file; Fable is the intended default.
- Main session model is the cap. Order: fable > opus > sonnet > haiku. If an agent's default sits above the
  main session model, override with `model:` down to the main session's model. Never up. E.g. main on
  Sonnet → `coder` runs Sonnet; `tester`/`finder`/`scribe` unchanged.
- `coder` runs the gates for its own change and reports output. `tester` is for standalone runs: full suite before commit, smoke passes, reproducing a reported failure.
- Review = main session reads the diff + gate output before committing. Don't re-run what `coder`/`tester` already ran.
