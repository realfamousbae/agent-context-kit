# Context protocol

<!-- Installed by agent-context-kit. Do not edit by hand: `install.sh --update` overwrites this file. -->

Several people and AI agents (Claude Code, Codex, others) work on this repository. They share one memory:
the `.context/` directory, transported by git. This file is the rule book. It overrides your own
note-taking habits.

`ctx` below means `.context/bin/ctx` (POSIX sh). On Windows without sh use `.context\bin\ctx.cmd` (cmd)
or `.context\bin\ctx.ps1` (PowerShell). Run `ctx help` for all commands.

## The one rule for writing

Write only what cannot be learned from the code and the commit message: why, what was tried and failed,
what is surprising, what is unfinished, what someone else must know. No narration, no restating the diff.

## Files

| File | What | When to write |
| --- | --- | --- |
| `MAP.md` | Modules, entry points, build/run/test commands, environment | When structure, commands or environment change |
| `GOTCHAS.md` | One line per trap or non-obvious behaviour, with the workaround | The moment you find it — not at the end |
| `DECISIONS.md` | A choice between options: context, decision, rejected alternatives | When you choose. Append only |
| `TASKS.md` | Now (owner, area) / Next / Blocked / Done | Claim at start, update at the end |
| `QUESTIONS.md` | Questions between participants and agents, with answers | Whenever you need someone else |
| `journal/*.md` | One entry per session | Draft at start, finished before the commit |
| `kit.json` | Kit version, records language, budgets, thresholds | Only via `ctx config` |
| `templates/<lang>/` | Templates in every supported language | Never (kit-owned) |

`DECISIONS.md`, `GOTCHAS.md` and `QUESTIONS.md` are append-only and merged with `merge=union`:
never rewrite or reorder old lines. Mark them instead (`[resolved …]`, `superseded by …`, ✅).

## Language

Everything written into `.context/` uses the language in `kit.json` (`"language"`), using the matching
templates from `templates/<lang>/`. Talk to the user in the user's language. Machine fields are always
Latin and never translated: frontmatter keys and values, IDs, file names, section anchors
(`<!-- ctx:… -->`), and the TASKS fields `@owner/agent`, `since`, `area:`, `waiting for:`, the status values
`active` / `superseded by D-…`, the marker `[resolved YYYY-MM-DD]` and the ✅ mark.

## IDs and time

- IDs: `<type>-<YYYYMMDD>-<initials>-<n>`, types `T` task, `D` decision, `G` gotcha, `Q` question.
  Example: `T-20261022-aa-1`. `n` is the next number for this author on this day; `ctx` computes it, so two
  people never collide and one person never reuses a number. Never shorten IDs in text.
- Initials come from `git config ctx.initials` (2–3 letters, unique per person); author from `git config ctx.author`.
- Journal file names use UTC: `journal/20261022-1130Z-alice-claude.md`. Frontmatter dates use local time
  with offset: `2026-10-22 14:30 +03:00`.

## Session start

1. If the repository has a remote and your working tree is clean, `git pull --rebase`. No network — say so
   and continue.
2. Read the brief: `ctx brief` (in Claude Code a SessionStart hook has already injected it — do not run it
   twice). It shows, in this order: warnings, open questions addressed to you, tasks in progress with their
   areas, active gotchas, other people's journal entries since your last one (including other branches),
   commits with code but without a journal entry, recent entries, the decisions index, the map.
3. Tell the user in 3–5 lines: what others did since your last session, what is in progress, which questions
   are addressed to you. This proves you read the context.
4. Claim the task before editing code: `ctx claim T-… --area "src/upload/ tests/test_upload*"`
   (no task yet: `ctx claim --new "Title" --area …`). The claim is committed (`ctx: claim T-…`).
   Pushing it depends on `push_claims`: `ask` (default) — show the user the push command and push only after
   they agree; `auto` — `ctx claim` pushes itself. `--push` / `--no-push` override once.
   - The area overlaps someone else's fresh claim → do not edit those files. Ask (`ctx ask @owner "…"`) and
     tell the user.
   - A claim older than `claim_stale_days` without activity is shown as stale. Ask its owner before ignoring it.
   - A one- or two-file task without overlaps may skip the separate push (`--no-push`); it travels with the code.
5. Start the journal draft: `ctx entry --agent <claude|codex> --model <model-id>`. It prints the path of your
   draft; calling it again returns the same draft.

## During the session

- Non-obvious behaviour or a workaround → a line in `GOTCHAS.md` right now (`ctx id G` gives the ID).
  Context may be compacted before the end and the detail lost.
- A choice between alternatives (library, architecture, format) → an entry in `DECISIONS.md`.
- Structure, commands or environment changed → update `MAP.md`.
- Need an answer from someone → `ctx ask @alice "…"`, `ctx ask @codex "…"` or `ctx ask @all "…"`.
  Answer with `ctx ask --answer Q-… "…"` (closes it with ✅; `--keep-open` to leave it open).
- Anything important you learned → into the draft's "Learned" section immediately.
- Area grew → `ctx claim T-… --area "…"` again.

Addressees: `@<author>` (that person and any of their agents), `@claude` / `@codex` (that agent of anyone),
`@all`.

## Session end

Trigger: the user says "done", "finish" or "ctx end", or you are about to commit. Run `ctx end` for the
checklist. Then:

1. Fill in the draft: done, learned, decisions (by ID), how it was verified, unfinished/risks, next step,
   for other participants, for humans (what you could not do yourself), files touched. Keep it under ~40 lines.
   `ctx entry --finish` checks the required sections (Done, How it was verified, Next step), drops empty
   optional sections and sets `status: done`.
2. Update `TASKS.md`: `ctx claim --done T-…` (moves it to Done) or `ctx claim --pause T-…` (keeps it in Now,
   marked paused, area released).
3. Commit the code and `.context/` in one commit, so context is tied to the code and reverts with it.
   Several commits in one session: each one updates the same entry. The commit-msg hook rejects code without
   a finished, staged journal entry in the same commit.
4. Push only by the project's rules and with the user's consent. The kit itself pushes nothing except claims
   with `push_claims: "auto"`.
5. Commits are made in the user's name: no `Co-Authored-By` lines for AI, no "generated by" signatures.

Trivial commits (typos, formatting) may skip the journal: put `[no-ctx]` in the commit message, or set
`CTX_SKIP=1`. Both are counted by `ctx status`.

## Compaction

`ctx brief` warns when `journal/` holds more than `compact_threshold_entries` entries or the brief exceeds
its byte budget. On "ctx compact" (one participant at a time — add a line to Now first):

1. `ctx compact` lists what is old: entries beyond the newest ones, answered questions, resolved gotchas.
2. Move lasting knowledge into `DECISIONS.md`, `GOTCHAS.md` and `MAP.md`.
3. Write the period summary to `journal/archive/SUMMARY-YYYY-MM.md`.
4. `ctx compact --apply` moves the old entries to `journal/archive/` and answered questions to the archive
   section of `QUESTIONS.md`.
5. Mark obsolete gotchas `[resolved YYYY-MM-DD] reason` and replaced decisions `superseded by D-…`.

Nothing is ever deleted. Compaction gets its own journal entry.

## Forbidden in `.context/`

- Secrets, keys, tokens, passwords, connection strings, internal URLs.
- Personal data: emails, phone numbers, addresses, anything about people beyond their author handle.
- Copies of code or long logs — link to files and commits instead.

The pre-commit hook scans `.context/` for common secret patterns and email addresses and rejects the commit.

## Commands

| Command | Purpose |
| --- | --- |
| `ctx brief [--short] [--budget N] [--no-fetch]` | Start-of-session summary. Never fails |
| `ctx claim T-… --area "…"` / `--new "Title"` / `--done T-…` / `--pause T-…` | Claim or release a task |
| `ctx entry --agent A --model M` / `--finish` / `--path` | Journal draft |
| `ctx ask @who "…"` / `--answer Q-… "…"` / `--list` | Questions |
| `ctx id T\|D\|G\|Q` | Print the next free ID |
| `ctx end` | End-of-session checklist |
| `ctx check --staged \| --soft \| --range A..B` | Enforcement (used by hooks and CI) |
| `ctx status [--days N]` | Bypasses, brief size, stale claims, old questions |
| `ctx compact [--apply]` | Prepare and perform compaction |
| `ctx config [key [value]]` | Read or change `kit.json` |
| `ctx migrate <path>…` | Move a legacy agent journal into `.context/` (see the kit's MIGRATION.md) |

User phrases: "ctx start", "ctx end", "ctx compact", "ctx status", "ctx ask".
