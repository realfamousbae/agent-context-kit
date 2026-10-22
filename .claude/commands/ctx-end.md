---
description: End of session — compare with the goal, finish the journal entry, release the claim
---
Follow "Exit" in `.context/PROTOCOL.md`:

1. `sh .context/bin/ctx end` — compare the result with the goal it shows.
2. Fill in the journal entry (only what the code and commit message do not say), and GOTCHAS / DECISIONS / MAP if you found something.
3. `sh .context/bin/ctx end --outcome met|partly|not-met`. If not met, tell the user what is missing.
4. Commit code and `.context/` together, in the user's name, without AI co-author lines. Push only if the user agrees.

$ARGUMENTS
