---
date: 2026-10-22 15:58 +03:00
author: realfamousbae
agent: claude
model: claude-opus-5-5
tasks: [T-20261022-rf-14]
status: done
outcome: met
---
## Done <!-- ctx:done -->
- Kit 0.2: context only at entry (start card, `ctx start --goal`), checkpoints (commit; push/deploy via PreToolUse) and exit (`ctx end --outcome`). No Stop hook. Goal and outcome live in the journal entry.
- Start card measured on a synthetic two-person project: 9421 → 2309 bytes injected per session; AGENTS block tells agents to open PROTOCOL.md (8.9 KB) only when unsure.

## Learned (not in the code) <!-- ctx:learned -->
- A live `claude -p` run showed the v2 AGENTS block made the agent call `ctx checkpoint push` itself before pushing — a duplicate of the hook plus a permission prompt; the block now says hooks show the card by themselves.
- In `claude -p` a PreToolUse "ask" acts as deny and Claude reads the reason — good for tests.
- Codex PreToolUse cannot "ask" yet; deny + CTX_CONFIRMED=1 is a speed bump only (D-20261022-rf-17).

## Decisions <!-- ctx:decisions -->
- D-20261022-rf-14 … D-20261022-rf-18 (rf-2 and rf-4 superseded)

## How it was verified <!-- ctx:verified -->
`sh tests/run.sh` and `TEST_SH=dash` (12 files incl. new t_session; t_agents feeds real PreToolUse JSON for both agents); shellcheck. Live: claude -p and codex exec on a synthetic project — start card, push stopped by the checkpoint. Not verified: interactive "ask" prompt UI, Windows sessions, real /compact.

## Unfinished / risks <!-- ctx:risks -->
- Claude `if` patterns are substring globs (`*deploy*`, `* apply*`): false positives only cost a confirmation, but `kubectl apply` in a read-only context also asks.
- Codex spawns the checkpoint hook on every Bash call (fast path is plain sh; slower on Windows).

## Next step <!-- ctx:next -->
- T-20261022-rf-13: measure the real per-session overhead in the pilot (now with the 0.2 flow).

## For other participants <!-- ctx:for-others -->
- @all: update with `install.sh --update`; the Stop hook disappears, PreToolUse hooks appear — Codex asks to re-approve them in /hooks.

## Files touched <!-- ctx:files -->
- `template/.context/bin/cmd/{brief,start,checkpoint,end,entry}.sh`, `ctx-lib.sh`, templates en/ru, `template/.claude/*`, `template/.codex/hooks.json`, `snippets/agents-block.md`, PROTOCOL, README, BOOTSTRAP, docs/agents.md, tests
