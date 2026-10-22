# agent-context-kit

Shared project memory for AI coding agents (Claude Code, Codex) and the people who work with them.
Git is the transport: no servers, no accounts, nothing to run in the background.

When several people and agents work on one repository, the useful context — why something was done, which
workaround is needed, who is editing which files, what someone asked — stays in chat windows and is lost.
The kit puts it into the repository, in a fixed format, and makes sure every session reads it at the start and
writes it at the end.

Context costs tokens — whatever is injected at the start stays in the conversation and is re-sent with every
request — so the kit uses it at three points only, and stays out of the way while the agent works by its own plan:

- **Entry.** A start card of ~2.5 KB at most is injected by a hook: questions addressed to the agent, live claims,
  one line per entry of others since its last session (also from other branches) with their notes for others,
  new gotchas, counts of the rest. When the user gives a task, `ctx start --goal "…" --area "…"` records the goal
  in the journal draft and claims the files; overlapping claims are refused until the owners agree.
- **Checkpoints.** A commit needs a finished journal entry staged with the code (commit hook; mid-session commits
  say `outcome: in-progress`). Before `git push`, a deploy or a publish, a hook compares the session with its
  goal: if the outcome is not `met`, the user is asked to confirm (Claude Code) or the agent is stopped with the
  checkpoint card and told to ask (Codex). Nothing runs for ordinary commands.
- **Exit.** `ctx end` shows the goal and the changes; `ctx end --outcome met|partly|not-met` finishes the entry
  and releases the claims. Not met → the agent tells the user what is missing.

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
powershell -NoProfile -ExecutionPolicy Bypass -File C:\path\to\agent-context-kit\install.ps1 --author bob --initials bo
```

If the project already has a hand-made agent journal, the installer stops and points to [MIGRATION.md](MIGRATION.md).

## What gets installed

```
AGENTS.md              ctx block at the top (Codex reads it; your own rules stay below)
CLAUDE.md              @AGENTS.md
.gitattributes         LF for scripts, CRLF for .cmd/.ps1, merge=union for append-only files
.claude/settings.json  SessionStart → start card, PreToolUse (push/deploy/publish only) → checkpoint, env CTX_AGENT (merged)
.claude/commands/      /ctx-start, /ctx-end, /ctx-compact, /ctx-ask
.codex/hooks.json      SessionStart → start card, PreToolUse → checkpoint (trusted projects; approve once: /hooks)
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
| `ctx brief [--full\|--short]` | Start card (default, `start_budget_bytes`), everything (`--full`), or the post-compaction view. Never fails |
| `ctx start --goal "…" --area "…"` | Entry: goal into the journal draft, claim the area |
| `ctx checkpoint [push\|deploy]` | Compare the work with the goal before an important step |
| `ctx end [--outcome met\|partly\|not-met]` | Exit: show goal and changes / finish the entry and release claims |
| `ctx claim T-… --area "src/x/ tests/x*"` | Claim a task and its files; refuses overlaps with fresh claims of others; commits; pushes per `push_claims` |
| `ctx claim --new "Title" --area …` / `--done T-…` / `--pause T-…` | New task / release |
| `ctx entry --agent claude --model <id>` | Create (or return) the journal draft (`ctx start` does it for you) |
| `ctx entry --finish [--outcome …]` | Check required sections, drop empty ones, mark done (default outcome `in-progress`) |
| `ctx ask @bob "…"` / `--answer Q-… "…"` | Questions between people and agents (`@claude`, `@codex`, `@all`) |
| `ctx id T\|D\|G\|Q` | Next collision-free ID: `T-20261022-aa-3` |
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
| Claude Code | SessionStart hook injects the start card; after compaction, the goal and draft come back. PreToolUse hooks filtered with `if` to push/deploy/publish commands ask the user to confirm while the session outcome is not `met`. No per-turn hooks |
| Codex | The ctx block at the top of `AGENTS.md`; in trusted projects `.codex/hooks.json`: SessionStart → start card, PreToolUse → checkpoint that stops push/deploy with the card until the user agrees (`CTX_CONFIRMED=1`; Codex has no "ask" yet). Approve the hooks once with `/hooks` |

Details and sources for every agent behaviour the kit relies on (hook output caps, Stop semantics, sandboxes,
Windows shells): [docs/agents.md](docs/agents.md).

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
