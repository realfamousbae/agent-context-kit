# agent-context-kit

Shared project memory for AI coding agents (Claude Code, Codex) and the people who work with them.
Git is the transport: no servers, no accounts, nothing to run in the background.

When several people and agents work on one repository, the useful context — why something was done, which
workaround is needed, who is editing which files, what someone asked — stays in chat windows and is lost.
The kit puts it into the repository, in a fixed format, and makes sure every session reads it at the start and
writes it at the end.

- **At the start** of every session the agent gets a brief (within a byte budget): questions addressed to it,
  tasks in progress and their file areas, active gotchas, what others did since its last session — including
  work on other branches — and commits that came without a journal entry.
- **Before editing**, the agent claims its area (`ctx claim`). Overlapping claims are refused until the owners agree.
- **During** the session, gotchas, decisions and questions go into their files immediately; the journal draft
  survives context compaction.
- **At the end**, a journal entry goes into the same commit as the code. A commit hook rejects code without it.

Works the same for Claude Code and Codex, on macOS, Linux and Windows (Git Bash, PowerShell, cmd).

## Connect a project

Tell your agent, in the project:

```
Connect the context protocol from https://github.com/realfamousbae/agent-context-kit — follow its BOOTSTRAP.md
```

The agent clones the kit to a temporary directory, runs the installer, picks the language of the records,
maps the project, recovers past decisions, fills in tasks, writes the first journal entry and shows you the diff.
You review and commit. Every other participant runs the installer once in their clone (it enables the git hooks
and sets their author handle):

```sh
sh /path/to/agent-context-kit/install.sh --author bob --initials bo
```

```powershell
& C:\path\to\agent-context-kit\install.ps1 --author bob --initials bo
```

If the project already has a hand-made agent journal, the installer stops and points to [MIGRATION.md](MIGRATION.md).

## What gets installed

```
AGENTS.md              ctx block at the top (Codex reads it; your own rules stay below)
CLAUDE.md              @AGENTS.md
.gitattributes         LF for scripts, CRLF for .cmd/.ps1, merge=union for append-only files
.claude/settings.json  SessionStart → ctx brief, Stop → ctx check --soft, env CTX_AGENT=claude (merged)
.claude/commands/      /ctx-start, /ctx-end, /ctx-compact, /ctx-ask
.githooks/             pre-commit (secrets, claim warnings), commit-msg (journal rule)
.github/workflows/     ctx.yml — only with --ci: pull-request report of commits without a journal entry
.context/
  PROTOCOL.md          the rules (kit-owned)
  MAP.md DECISIONS.md GOTCHAS.md TASKS.md QUESTIONS.md
  AUTHORS              handle → initials, so IDs never collide
  kit.json             version, language, budgets, thresholds
  journal/             one entry per session; archive/ after compaction
  templates/en|ru/     record templates
  bin/ctx              entry point (POSIX sh); ctx.cmd and ctx.ps1 for Windows
```

## Commands

`ctx` is `.context/bin/ctx` (`sh .context/bin/ctx …`; on Windows `.context\bin\ctx.cmd …` or `ctx.ps1`).

| Command | What it does |
| --- | --- |
| `ctx brief [--short]` | Start-of-session summary in priority order, within `brief_budget_bytes`. Never fails |
| `ctx claim T-… --area "src/x/ tests/x*"` | Claim a task and its files; refuses overlaps with fresh claims of others; commits; pushes per `push_claims` |
| `ctx claim --new "Title" --area …` / `--done T-…` / `--pause T-…` | New task / release |
| `ctx entry --agent claude --model <id>` | Create (or return) the session's journal draft |
| `ctx entry --finish` | Check required sections, drop empty ones, mark done |
| `ctx ask @bob "…"` / `--answer Q-… "…"` | Questions between people and agents (`@claude`, `@codex`, `@all`) |
| `ctx id T\|D\|G\|Q` | Next collision-free ID: `T-20261022-aa-3` |
| `ctx end` | End-of-session checklist |
| `ctx status` | Bypass rate, brief size, stale claims, old questions |
| `ctx compact [--apply]` | Archive old entries and answered questions |
| `ctx config [key [value]]` | `kit.json`: `language`, `push_claims`, `brief_budget_bytes`, `claim_stale_days`, … |
| `ctx migrate <files>` | Move a legacy journal into `.context/` |

Users can also just say "ctx start", "ctx end", "ctx compact", "ctx status", "ctx ask".

## Enforcement

| Layer | Mechanism |
| --- | --- |
| Everyone (git) | `commit-msg`: code without a finished journal entry staged in the same commit is rejected. Bypass for trivia: `[no-ctx]` in the message or `CTX_SKIP=1` (both counted by `ctx status`). Strips AI `Co-Authored-By` lines (`strip_ai_coauthor`) |
| Everyone (git) | `pre-commit`: secret and personal-data patterns in `.context/`; warning when you touch someone else's claimed files |
| Everyone (CI) | `ctx check --range base..HEAD` in pull requests (`--ci`) catches `--no-verify` |
| Claude Code | SessionStart hook injects the brief; after compaction, the short brief and your draft. Stop hook reminds once per session about the journal, blocks only after `ctx end` with an unfinished entry |
| Codex | The ctx block at the top of `AGENTS.md`; the git hooks and CI above |

The kit never pushes anything except claims with `push_claims: "auto"`, and never adds AI attribution.

## Language

The kit itself is English. The records in `.context/` use the project's language — `en` or `ru` today
(add one by adding `template/i18n/<lang>/`). Section anchors (`<!-- ctx:done -->`), IDs, frontmatter and the
machine fields of TASKS stay Latin, so the scripts work in any language. Change it with `ctx config language ru`.

## Requirements and portability

git and a POSIX shell (on Windows: Git for Windows, whose bash the `.cmd`/`.ps1` wrappers find — never WSL's
`bash.exe`). `jq` or Python are used to merge `.claude/settings.json` if present; without them the installer
prints the fragment to paste. No GNU- or BSD-only flags; every network call has a timeout and is optional.
CI runs the test suite on Ubuntu (dash and bash), macOS (bash 3.2) and Windows (Git Bash, PowerShell 5.1 and 7, cmd).

## Update and uninstall

```sh
sh <kit>/install.sh --update      # refresh PROTOCOL.md, bin/, templates, hooks; project data untouched
sh <kit>/install.sh --uninstall   # remove the AGENTS.md block, hooks and settings; .context/ stays
```

## Development

```sh
sh tests/run.sh                  # all tests on temporary git repositories
TEST_SH=dash sh tests/run.sh     # the same under dash
```

The kit's own development is logged with the kit: see [.context/](.context/).

## License

MIT — see [LICENSE](LICENSE).
