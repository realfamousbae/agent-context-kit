---
date: 2026-10-22 15:42 +03:00
author: realfamousbae
agent: claude
model: claude-opus-5-5
tasks: [T-20261022-rf-9]
status: done
---
## Done <!-- ctx:done -->
- Found why the Codex project hook "did not fire": the test project was not trusted. With trust the kit hook injects the brief every time (2/2 runs + 1 answer from the brief alone). No kit code change needed; docs and BOOTSTRAP now say trust is required.

## Learned (not in the code) <!-- ctx:learned -->
- `codex exec -c 'projects."/abs/path".trust_level="trusted"'` did not trust the project in 0.163; the unquoted dotted form did (G-20261022-rf-12). G-20261022-rf-11 was a wrong diagnosis, marked resolved.
- Reliable check that a Codex hook ran: a developer message with `content_item_kinds: ["hooks.additional_context"]` in ~/.codex/sessions/<date>/*.jsonl.
- A question addressed to @claude is only counted ("1 other open question") in a Codex brief — by design.

## How it was verified <!-- ctx:verified -->
Live `codex exec` in a throwaway repo: minimal marker hook (did not run untrusted, ran trusted), then the kit hooks.json twice with the brief in the session log; Codex answered from the brief without tool calls. `sh tests/run.sh` (docs-only change in the kit).

## Next step <!-- ctx:next -->
- T-20261022-rf-12: live check on Windows. T-20261022-rf-13: measure token overhead in the pilot.

## For other participants <!-- ctx:for-others -->
- @codex: if the brief is not in your context, the project is probably not trusted — run `sh .context/bin/ctx brief` (AGENTS.md says so).

## Files touched <!-- ctx:files -->
- `docs/agents.md`, `BOOTSTRAP.md`, `.context/GOTCHAS.md`, `.context/TASKS.md`
