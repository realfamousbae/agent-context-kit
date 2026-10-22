# MIGRATION — moving an existing agent journal into agent-context-kit

Projects often already have a hand-made journal for agents: `NOTES.md`, `CHANGES.md`, `docs/ai-journal/`,
rules about it in `AGENTS.md`. Running a second protocol on top of it splits the memory in two, so the
installer stops (exit code 3) and sends you here.

Migration changes the protocol for everyone: tell the user, and do it as a separate commit.

## 1. Install in migration mode

```sh
sh <kit>/install.sh --migrate --author <handle> --initials <xx> --language <en|ru>
```

Same as a normal install, but it does not stop on the legacy files.

## 2. Move the old files and extract what is still alive

```sh
sh .context/bin/ctx migrate NOTES.md CHANGES.md docs/ai-journal
```

- The files are moved to `.context/journal/archive/legacy/` with `git mv`, so `git log --follow` keeps their history.
- Bullets under recognisable headings are copied into the new files, marked
  "(restored from the legacy journal, verify)":

  | Legacy heading (en / ru) | Goes to |
  | --- | --- |
  | Gotchas, Pitfalls, Traps / Ловушки, Грабли | GOTCHAS |
  | Decisions / Решения | DECISIONS |
  | In progress, Now, Current / В работе, Сейчас | TASKS → Now |
  | Questions / Вопросы | QUESTIONS (a leading `@name` becomes the addressee, else `@all`; answered ones ✅ are skipped) |
  | Ideas, TODO, Next, Backlog / Идеи, План, Дальше | TASKS → Next |

## 3. Review what was restored

The extraction is mechanical. Read the legacy files yourself and:

- delete restored items that are obsolete, rewrite unclear ones, add what the headings did not catch
  (gotchas hidden in session logs are the most valuable part);
- give decisions a proper Context / Rejected;
- put owners and areas on Now tasks only if someone is really working on them.

## 4. Summarise the old journal

Write `.context/journal/archive/SUMMARY-legacy.md`, at most ~2 KB: the period it covers, who worked, the main
milestones, and where to look in `legacy/` for details.

## 5. Replace the old rules

In `AGENTS.md`, delete the old journal rules (the ctx block at the top replaces them). Keep every other
project rule — security, language, commit format — outside the block.

## 6. Tell everyone and commit

- `sh .context/bin/ctx ask @all "The old journal (NOTES.md, CHANGES.md) is retired; history is in .context/journal/archive/legacy/. Please run the installer in your clone."`
- A journal entry for the migration (`ctx entry`, `ctx entry --finish`).
- One separate commit after the user agrees. Every participant re-runs the installer in their clone.
