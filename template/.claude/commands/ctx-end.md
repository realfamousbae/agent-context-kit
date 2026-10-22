---
description: End of session — finish the journal entry, release the claim, commit code and context together
---
Run `sh .context/bin/ctx end` and follow its checklist ("Session end" in `.context/PROTOCOL.md`):

1. Fill in your journal draft — only what is not in the code or the commit message — then `sh .context/bin/ctx entry --finish`.
2. Release your claims: `sh .context/bin/ctx claim --done T-…` or `--pause T-…`.
3. Make sure GOTCHAS, DECISIONS and MAP have what you found.
4. Commit code and `.context/` in one commit, in the user's name, without AI co-author lines. Push only if the user agrees.

$ARGUMENTS
