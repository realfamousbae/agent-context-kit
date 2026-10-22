---
description: Ask another participant or agent a question through .context/QUESTIONS.md, or answer one
---
Questions go through `.context/QUESTIONS.md`, never only in chat:

- Ask: `sh .context/bin/ctx ask @<author|claude|codex|all> "question" --task T-…` (add `--commit` to commit it right away; pushing follows `push_claims`).
- Answer: `sh .context/bin/ctx ask --answer Q-… "answer"` (closes it with ✅; `--keep-open` to keep it open).
- List: `sh .context/bin/ctx ask --list`.

Request: $ARGUMENTS
