# BOOTSTRAP — connecting agent-context-kit to a project

Instructions for the AI agent the user asked to "connect the context protocol from
https://github.com/realfamousbae/agent-context-kit". Talk to the user in their language; write files as described.

## 1. Get the kit and run the installer

Clone the kit into a temporary directory (not inside the project), then run the installer from the project root:

```sh
git clone --depth 1 https://github.com/realfamousbae/agent-context-kit.git "$TMPDIR/agent-context-kit"
sh "$TMPDIR/agent-context-kit/install.sh" --author <handle> --initials <2-3 letters> --language <en|ru>
```

Windows PowerShell (Git for Windows must be installed; the script finds its bash):

```powershell
git clone --depth 1 https://github.com/realfamousbae/agent-context-kit.git $env:TEMP\agent-context-kit
& $env:TEMP\agent-context-kit\install.ps1 --author <handle> --initials <xx> --language <en|ru>
```

- `--author`: a short handle for the human (ask if unsure; never derive it from an email). `--initials`: 2–3 letters,
  unique in the project — the installer refuses initials registered by someone else in `.context/AUTHORS`.
- Optional: `--push-claims auto` (claims are pushed by `ctx claim`; default `ask`), `--ci` (pull-request check),
  `--chain-hooks` (the project already has git hooks — keep them running after ours).
- Exit code 3 means an existing agent journal was found: do [MIGRATION.md](MIGRATION.md) first, starting with
  `install.sh --migrate`.
- If the sandbox cannot write `.git` (hooks path, git config, staging), the installer prints the commands —
  give them to the user.

## 2. Decide the language of the records

Look at the documentation written for humans: `README*`, `docs/`, existing notes and comments in issues.
Ignore commit messages — they are often English even in projects that are not. If it is clearly one language,
use it (`sh .context/bin/ctx config language ru`). If it is mixed or there is no documentation — ask the user.
Tell the user which language you chose.

## 3. Migrate an existing journal

If step 1 reported a legacy journal, follow [MIGRATION.md](MIGRATION.md) now, before filling anything else.

## 4. Fill in `.context/MAP.md`

Scan the repository: modules and what they do, entry points, build/run/test commands (verify them if cheap),
environment (runtimes, services, required variables — names only, never values). Short and factual.

## 5. Recover decisions already made

From the README, docs, existing notes and the commit history (`git log --stat`, big refactors, dependency
changes) write the important past decisions into `.context/DECISIONS.md` with `ctx id D` IDs. Mark each one
as recovered: `- Context: recovered from <source>, verify`. Only decisions someone would otherwise re-litigate.

## 6. Fill in `.context/TASKS.md`

From TODO/FIXME in the code, open issues (if you can read them) and what the user tells you. One line each,
`ctx id T` for IDs, Next or Blocked; Now only for what is actually being worked on.

## 7. First journal entry

`sh .context/bin/ctx entry --agent <claude|codex> --model <model id>` — record the installation: what was set up,
the chosen language, what you could not determine (put it under "For humans"). Then `ctx entry --finish`.

## 8. Show the user, do not commit by yourself

Show `git status` and the diff summary, the chosen language and the identity. Commit only after the user agrees —
in the user's name, without AI co-author lines. One commit: the kit files, the filled-in context and the entry.

Every other participant, after pulling, runs the installer once in their own clone (it enables the hooks
and sets `ctx.author` / `ctx.initials`):

```sh
sh <kit>/install.sh --author <their handle> --initials <xx>
```
