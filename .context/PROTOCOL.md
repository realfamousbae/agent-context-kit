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
| `GOTCHAS.md` | One line per trap or non-obvious behaviour, with the workaround | When found; at the next checkpoint at the latest |
| `DECISIONS.md` | A choice between options: context, decision, rejected alternatives | When you choose. Append only |
| `TASKS.md` | Now (owner, area) / Next / Blocked / Done | Claim at start, update at the end |
| `QUESTIONS.md` | Questions between participants and agents, with answers | Whenever you need someone else |
| `journal/*.md` | One entry per session | Draft with the goal at entry (`ctx start`), finished at commits and exit |
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

## When context is used

Context costs tokens: whatever is injected at the start stays in the conversation and is re-sent with every
request. So the protocol touches context at three points only — entry, checkpoints, exit — and stays out of the
way during routine work, where you follow your own plan.

## Entry

1. If the repository has a remote and your working tree is clean, `git pull --rebase`. No network — say so
   and continue.
2. The start card: in Claude Code and Codex a SessionStart hook injects it (`ctx brief`, ~2.5 KB); otherwise run
   `ctx brief`. It holds warnings, questions addressed to you, live claims, one line per entry of others since
   your last one (also from other branches) with their notes for others, gotchas new since then, and counts of
   the rest. Everything else is on demand: `ctx brief --full`, or the files themselves.
3. Tell the user in 2–4 lines what is new from others and which questions are addressed to you.
4. When the user gives a task, one call records the goal and claims the area:
   `ctx start --goal "<what the user wants, and how we will know it is done>" --area "src/upload/ tests/test_upload*"`
   (`--plan "…"` optional; an existing task: `ctx start --goal "…" T-…`). The goal goes into your journal draft;
   every checkpoint compares against it.
   - The area overlaps someone else's fresh claim → the claim is refused: do not edit those files; ask
     (`ctx ask @owner "…"`) and tell the user.
   - A claim older than `claim_stale_days` without activity is shown as stale. Ask its owner before ignoring it.
   - The claim is committed (`ctx: claim T-…`); pushing follows `push_claims`: `ask` (default) — show the user the
     push command; `auto` — pushed at once; `--push` / `--no-push` override once.

## During work

Work by your plan. Do not re-read `.context/` unless something is unclear. Keep findings for the next checkpoint
at the latest: a trap or workaround → a line in `GOTCHAS.md` (`ctx id G`), a choice between options →
`DECISIONS.md`, structure or commands changed → `MAP.md`, something only another person can answer →
`ctx ask @alice "…"` / `@codex` / `@all` (answer with `ctx ask --answer Q-… "…"`). Long sessions may write
important findings into the draft right away: it survives context compaction, the conversation may not.

Addressees: `@<author>` (that person and any of their agents), `@claude` / `@codex` (that agent of anyone), `@all`.

## Checkpoints

Before a step that is hard to undo, compare the result with the goal:

| Step | What happens |
| --- | --- |
| `git commit` | The commit-msg hook wants a finished journal entry staged with the code: fill it in and run `ctx entry --finish` (outcome `in-progress` by default — no premature verdict). Several commits in a session update the same entry. |
| `git push`, deploy, publish | `ctx checkpoint push` shows the goal, what changed, files outside your claim, others' claims you touch, open questions. Goal not met or unclear → tell the user and ask before going on. In Claude Code a PreToolUse hook does this for you and asks the user to confirm while the outcome is not `met`; in Codex the hook stops the command with the same card (Codex cannot ask yet) — after the user agrees, rerun it prefixed with `CTX_CONFIRMED=1`. |

## Exit

Trigger: the user says "done", "finish" or "ctx end".

1. `ctx end` shows the goal, the changes and what the entry still lacks. Compare honestly.
2. Fill in the entry: done, learned, decisions (by ID), how it was verified, unfinished/risks, next step, for other
   participants, for humans (what you could not do yourself). Under ~40 lines, only what the code and commit
   message do not say.
3. `ctx end --outcome met|partly|not-met` finishes the entry with that outcome and releases your claims (Done when
   met, paused otherwise). Not met → tell the user what is missing and what you propose.
4. Commit code and `.context/` together, in the user's name, without AI co-author lines. Push only with the
   user's consent.

Trivial commits (typos, formatting) may skip the journal: `[no-ctx]` in the commit message, or `CTX_SKIP=1`.
Both are counted by `ctx status`.

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
| `ctx brief [--full\|--short] [--budget N] [--no-fetch]` | Start card (default), everything, or the post-compaction view. Never fails |
| `ctx start --goal "…" [--area "…"] [T-…\|--new "Title"]` | Entry: goal into the journal draft, claim the area |
| `ctx checkpoint [push\|deploy\|commit]` | Compare the work with the goal before an important step |
| `ctx end [--outcome met\|partly\|not-met]` | Exit: show goal and changes / finish the entry and release claims |
| `ctx claim T-… --area "…"` / `--new "Title"` / `--done T-…` / `--pause T-…` | Claim or release a task |
| `ctx entry --agent A --model M` / `--finish [--outcome …]` / `--path` | Journal draft (`ctx start` creates it for you) |
| `ctx ask @who "…"` / `--answer Q-… "…"` / `--list` | Questions |
| `ctx id T\|D\|G\|Q` | Print the next free ID |
| `ctx check --staged \| --range A..B` | Enforcement (git hooks and CI) |
| `ctx status [--days N]` | Bypasses, brief size, stale claims, old questions |
| `ctx compact [--apply]` | Prepare and perform compaction |
| `ctx config [key [value]]` | Read or change `kit.json` |
| `ctx migrate <path>…` | Move a legacy agent journal into `.context/` (see the kit's MIGRATION.md) |

User phrases: "ctx start", "ctx end", "ctx compact", "ctx status", "ctx ask".
