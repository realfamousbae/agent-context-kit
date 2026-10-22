<!-- ctx:begin v2 -->
## Shared project context (agent-context-kit)
Project memory for people and agents lives in `.context/`; `ctx` = `sh .context/bin/ctx` (Windows: `.context\bin\ctx.cmd`).
Use it at three points only — not during routine work:
- **Start.** If no ctx card was injected at session start, run `ctx brief`. Tell the user in 2–4 lines what is new from others and which questions are for you. When the user gives a task: `ctx start --goal "<what, and how we know it is done>" --area "<paths>"`, then work by your own plan.
- **Checkpoints — before git push, a deploy, or publishing:** compare the result with your goal; not met or unclear → ask the user before going on. Hooks of Claude Code and Codex show the checkpoint card by themselves; without them run `ctx checkpoint push`. Commits need a finished journal entry (`ctx entry --finish`; outcome `in-progress` is fine mid-session).
- **End:** `ctx end`, compare with the goal, then `ctx end --outcome met|partly|not-met`; if not met, tell the user what is missing.
Record in `.context/` (language from `.context/kit.json`) only what the code and commit message do not say: traps → GOTCHAS, choices → DECISIONS, questions to others → `ctx ask @who "…"`. Write them at the next checkpoint at the latest.
No secrets or personal data in `.context/`. No AI co-author lines in commits. Rules, only when unsure: `.context/PROTOCOL.md`.
<!-- ctx:end -->
