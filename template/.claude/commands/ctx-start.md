---
description: Start of session — read the shared project context, claim the task, open the journal draft
---
Follow "Session start" in `.context/PROTOCOL.md`:

1. Unless the brief was already injected at session start, run `sh .context/bin/ctx brief`.
2. Tell the user in 3–5 lines: what others did since your last session, what is in progress, which questions are addressed to you.
3. Find the user's task in `.context/TASKS.md` and claim it before editing: `sh .context/bin/ctx claim T-… --area "…"` (or `--new "Title"`). If the area overlaps someone's claim, ask with `ctx ask` and tell the user.
4. Open your journal draft: `sh .context/bin/ctx entry --agent claude --model <your model id>`.

$ARGUMENTS
