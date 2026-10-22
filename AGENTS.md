<!-- ctx:begin v1 -->
## Shared project context — mandatory
Several people and agents work on this project. Project memory lives in `.context/`.
- At session start run `sh .context/bin/ctx brief` (Windows without sh: `.context\bin\ctx.cmd brief`);
  skip if a hook already injected it. Tell the user in 3–5 lines what others did, what is in progress,
  and which questions are addressed to you.
- Before editing code, claim your area: `ctx claim`. If it overlaps someone else's claim, ask first (`ctx ask`).
- Rules: `.context/PROTOCOL.md`. They override your own note-taking habits.
- Write everything in `.context/` in the language set in `.context/kit.json`. Talk to the user in their language.
- Non-obvious behaviour → GOTCHAS now. Decision → DECISIONS. Structure → MAP. Question to others → `ctx ask`.
- Journal: `ctx entry --agent <claude|codex> --model <id>` at start, fill it in, `ctx entry --finish` before committing.
- Code without a finished journal entry in the same commit is rejected by the commit hooks.
- No secrets, keys, tokens, personal data or internal URLs in `.context/`.
- No `Co-Authored-By` or AI attribution in commits.
- User commands: "ctx start", "ctx end", "ctx compact", "ctx status", "ctx ask".
<!-- ctx:end -->
