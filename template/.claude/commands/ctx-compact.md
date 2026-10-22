---
description: Compact the shared journal — move lasting knowledge into DECISIONS/GOTCHAS/MAP and archive old entries
---
Follow "Compaction" in `.context/PROTOCOL.md`:

1. Add a line to Now in `.context/TASKS.md` (`sh .context/bin/ctx claim --new "Compact the journal" --area ".context/"`).
2. `sh .context/bin/ctx compact` lists what is old. Read those entries.
3. Move lasting knowledge to DECISIONS, GOTCHAS and MAP; mark obsolete gotchas `[resolved YYYY-MM-DD] reason` and replaced decisions `superseded by D-…`.
4. Write the period summary to `.context/journal/archive/SUMMARY-YYYY-MM.md`.
5. `sh .context/bin/ctx compact --apply`, then a journal entry about the compaction. Nothing is deleted.

$ARGUMENTS
