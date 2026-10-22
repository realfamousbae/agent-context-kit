# Decisions

<!-- Append only, newest at the bottom. Never rewrite an old decision: add a new one and mark the old one "superseded by D-…". -->
<!-- ### D-YYYYMMDD-ii-n — Title -->
<!-- - Context: what forced the choice -->
<!-- - Decision: what was chosen -->
<!-- - Rejected: alternatives and why -->
<!-- - By: author/model, T-… -->
<!-- - Status: active | superseded by D-… -->

### D-20261022-rf-1 — Journal rule lives in commit-msg, not pre-commit
- Context: the plan put "code without a journal entry → reject" into pre-commit and the `[no-ctx]` bypass into commit-msg. Git runs pre-commit before the message exists, so pre-commit cannot see `[no-ctx]`.
- Decision: commit-msg runs `ctx check --commit-msg` (journal rule, `[no-ctx]`, `CTX_SKIP=1` + `Ctx-Skip:` trailer, AI co-author stripping); pre-commit keeps secrets and claim warnings.
- Rejected: a marker file written by pre-commit and read by commit-msg (state on disk, breaks in read-only sandboxes).
- By: realfamousbae/claude-opus-5-5
- Status: active

### D-20261022-rf-2 — Claude Code SessionStart brief capped at 9.5 KB (plan: ~24 KB)
- Context: Claude Code docs (hooks, checked 2026-10-22): hook output added to context is capped at 10,000 characters; longer output becomes a file path plus a 2,000-character preview. The plan's 24 KB brief would arrive as a preview.
- Decision: `ctx brief --hook` uses `hook_budget_bytes` = 9500 and ends with "Full brief: sh .context/bin/ctx brief" when shortened. `brief_budget_bytes` (24000) stays for manual runs and Codex.
- Rejected: JSON `additionalContext` (same cap); splitting over several hooks (order and caps not guaranteed).
- By: realfamousbae/claude-opus-5-5
- Status: superseded by D-20261022-rf-14

### D-20261022-rf-3 — PreCompact is not used; SessionStart(compact) restores context
- Context: plan item 11 asked to verify. Docs: PreCompact output is not added to the model context (systemMessage discarded; exit 2 only blocks compaction). SessionStart has a `compact` matcher whose stdout is added.
- Decision: `SessionStart` matcher `compact` → `ctx brief --hook --short` (claims, questions, gotchas, the draft). Same for Codex (`source: compact`).
- Rejected: PreCompact hook.
- By: realfamousbae/claude-opus-5-5
- Status: active

### D-20261022-rf-4 — Stop hook: per-turn, one reminder per session, block only after `ctx end`
- Context: docs confirm Stop fires whenever Claude finishes responding (per turn); exit 2 sends stderr to Claude as the reason to continue; `stop_hook_active` is true when already continued by a Stop hook; after 8 consecutive blocks Claude Code ends the turn anyway.
- Decision: as planned, plus: no hook input at all → never block (cannot see `stop_hook_active`); reminder state in `.git/ctx/reminded-<session_id>`, silent if `.git` is not writable.
- Rejected: blocking every turn with changes and no entry (nags, loops).
- By: realfamousbae/claude-opus-5-5
- Status: superseded by D-20261022-rf-15

### D-20261022-rf-5 — Hook commands use `sh "${CLAUDE_PROJECT_DIR}/…"` and follow the `cwd` field
- Context: docs: Claude Code runs hooks in Git Bash on Windows (PowerShell only without Git Bash); `${CLAUDE_PROJECT_DIR}` is the recommended spelling; in worktrees `CLAUDE_PROJECT_DIR` stays at the main checkout while the input `cwd` follows the session.
- Decision: one command form for all OSes; `--hook` reads the hook JSON and `cd`s to `cwd`. Plan's fallback to `ctx.cmd` for Claude Code is not needed.
- Rejected: `$CLAUDE_PROJECT_DIR` bare form (breaks under PowerShell); relying on the hook process cwd.
- By: realfamousbae/claude-opus-5-5
- Status: active

### D-20261022-rf-6 — Codex gets hooks: `.codex/hooks.json` (plan assumed AGENTS.md only)
- Context: Codex CLI 0.163 docs: hooks on by default; project hooks in `<repo>/.codex/hooks.json`, trusted per hash via `/hooks`; SessionStart sources incl. `compact`, default model-visible limit ~2,500 tokens (`additionalContextLimit`); Stop must print JSON on exit 0; commands run in the session cwd; Windows override `commandWindows`.
- Decision: install `.codex/hooks.json`: SessionStart → `ctx brief --hook --format codex` (JSON additionalContext, limit 8000/3000 tokens), Stop → `ctx check --soft --format codex` which always exits 0 with `{}` or `{"decision":"block","reason":…}`. Paths via `$(git rev-parse --show-toplevel)`; Windows via `powershell -NoProfile -ExecutionPolicy Bypass -Command "& … ctx.ps1 …"`.
- Rejected: exit 2 for Codex Stop — `powershell -Command` turns exit 2 into 1 (seen in CI), which Codex would treat as a hook failure.
- By: realfamousbae/claude-opus-5-5
- Status: active

### D-20261022-rf-7 — Codex sandbox: no temp files in brief, commands printed instead of commits
- Context: Codex docs: workspace-write keeps `.git`, `.codex`, `.agents` read-only and network off; read-only mode writes nothing. A live `codex exec -s read-only` run showed `ctx brief` printing nothing (it needed mktemp).
- Decision: brief keeps sections in shell variables (no temp files); fetch failure is a warning; `ctx claim` / `ctx ask --commit` print the git command for the user; installer prints what to merge if `.codex/` is not writable. AGENTS.md (32 KiB combined limit) keeps the ctx block ~1.5 KB and first; installer warns about `AGENTS.override.md`.
- By: realfamousbae/claude-opus-5-5
- Status: active

### D-20261022-rf-8 — Initials registry `.context/AUTHORS` (merge=union)
- Context: the plan said the installer checks that initials are not taken "in the journal", but IDs in the journal do not reliably say whose initials they are (people mention others' IDs).
- Decision: append-only `.context/AUTHORS` (`handle initials` per line). The installer refuses taken initials and picks free ones automatically when not given.
- Rejected: scanning journal IDs; a key per person in kit.json (merge conflicts, kit.json stays flat).
- By: realfamousbae/claude-opus-5-5
- Status: active

### D-20261022-rf-9 — Every language's templates are installed; machine fields stay Latin
- Context: `ctx config language` must work offline after install, and scripts must parse records in any language.
- Decision: `.context/templates/<lang>/` holds all languages (a few KB). Anchors, IDs, frontmatter and TASKS fields (`@owner/agent`, `since`, `area:`), `Status: active|superseded by`, `[resolved …]`, ✅ are Latin in every language.
- By: realfamousbae/claude-opus-5-5
- Status: active

### D-20261022-rf-10 — Byte semantics and no MSYS path conversion inside ctx
- Context: CI showed gawk (Ubuntu) counting characters where mawk/BWK awk count bytes, and Git Bash rewriting `origin/x:.context/TASKS.md` into a Windows path list.
- Decision: ctx-lib exports `LC_ALL=C`, `MSYS_NO_PATHCONV=1`, `MSYS2_ARG_CONV_EXCL=*`; ctx only passes relative paths to git.
- By: realfamousbae/claude-opus-5-5
- Status: active

### D-20261022-rf-11 — `.context/**` is LF in every checkout; `.cmd`/`.ps1` CRLF
- Context: the plan listed eol rules for scripts only; with `core.autocrlf=true` records got CRLF, mixed with LF lines written by ctx.
- Decision: the `.gitattributes` block sets `.context/** text eol=lf`, then CRLF for `.context/bin/*.cmd|*.ps1` and LF for our two git hooks. Project-wide `*.sh` rules are left to the project.
- By: realfamousbae/claude-opus-5-5
- Status: active

### D-20261022-rf-12 — `strip_ai_coauthor` defaults to true
- Context: plan made stripping optional; the protocol forbids AI attribution and this repository's owner requires it.
- Decision: commit-msg removes `Co-Authored-By:` lines naming AI tools and "Generated with …" lines unless `ctx config strip_ai_coauthor false`. Human co-authors are kept.
- By: realfamousbae/claude-opus-5-5
- Status: active

### D-20261022-rf-13 — Claude Code slash commands stay in `.claude/commands/`
- Context: docs (2026-10-22): custom commands were merged into skills; `.claude/commands/*.md` is the older form and keeps working.
- Decision: keep `/ctx-start`, `/ctx-end`, `/ctx-compact`, `/ctx-ask` as command files (explicit invocation only).
- Rejected: skills — Claude may invoke them on its own judgement from the description; revisit in the pilot.
- By: realfamousbae/claude-opus-5-5
- Status: active

### D-20261022-rf-14 — Context at entry, checkpoints and exit only; small start card
- Context: the user pointed out that cheap subscriptions pay for every token. Whatever a SessionStart hook injects stays in the transcript and is re-sent (cached) with every request; the v0.1 hook brief was up to 9.5 KB (Claude) / 24 KB (Codex), plus agents read PROTOCOL.md (8.9 KB).
- Decision: the default `ctx brief` is a start card capped by `start_budget_bytes` (2500): warnings, questions for me, live claims, one line per entry of others since my last one (with their notes for others, deduplicated), gotchas new since then, counts of the rest. `--full` keeps the old brief on demand; `resume` injects only warnings and questions; `compact` brings back goal, draft and claims. The AGENTS block v2 says to use context at three points only and to open PROTOCOL.md only when unsure. Measured on a synthetic two-person project (8 entries, 12 gotchas, 6 decisions, 3 KB map): 9421 → 2309 bytes injected.
- Rejected: a "lean profile" for cheap plans (two behaviours to maintain); no start context at all (claims and questions would be missed).
- By: realfamousbae/claude-opus-5-5, T-20261022-rf-14
- Status: active

### D-20261022-rf-15 — No Stop hook; the journal is enforced at commits
- Context: Stop runs after every response; even silent, it is per-turn machinery, and its reminder cost a model turn.
- Decision: no Stop hook in the installed settings (an update removes the 0.1 one). The commit-msg hook still requires a finished entry; `ctx end` is the exit checkpoint. `ctx check --soft` stays available.
- Rejected: keeping a silent Stop guard for `ctx end` (adds a process per turn for little value).
- By: realfamousbae/claude-opus-5-5, T-20261022-rf-14
- Status: active

### D-20261022-rf-16 — Goal and outcome live in the journal entry
- Context: checkpoints need something to compare against, and a verdict that scripts can read in any language.
- Decision: `ctx start --goal` writes the goal (and optional plan) into the draft (new `ctx:goal`, `ctx:plan` sections, required only when the anchor exists, so 0.1 drafts still finish). Frontmatter `outcome: in-progress | met | partly | not-met`; `ctx entry --finish` defaults to in-progress so mid-session commits need no premature verdict; `ctx end --outcome …` sets the verdict and releases claims (Done when met, paused otherwise).
- By: realfamousbae/claude-opus-5-5, T-20261022-rf-14
- Status: active

### D-20261022-rf-17 — Push/deploy checkpoint through PreToolUse: Claude asks the user, Codex is stopped
- Context: Claude Code PreToolUse supports `if` filters and `permissionDecision: "ask"`; `allow` would bypass the user's own permission prompts. Codex PreToolUse has no `if` and does not support `ask` yet (parsed, reported as a failed hook).
- Decision: Claude: handlers with `if` for `git push*`, `*deploy*`, `*publish*`, `* apply*`, `*docker push*`, `*helm *`, `*railway up*`, `*release create*` (Bash and PowerShell); the hook prints nothing when the session outcome is `met`, otherwise `ask` with the checkpoint card; never `allow`. Codex: matcher `Bash`, a plain-sh fast path exits for other commands; otherwise `deny` with the card and "ask the user, then rerun with CTX_CONFIRMED=1". The prefix is a speed bump the model could add itself, not enforcement. Extra patterns: kit.json `checkpoint_patterns` (Codex and the sh fast path; Claude needs an extra `if` handler).
- Rejected: a git pre-push hook (cannot tell agents from humans, and runs after the decision); `additionalContext` on allowed commands (arrives after the command ran).
- By: realfamousbae/claude-opus-5-5, T-20261022-rf-14
- Status: active

### D-20261022-rf-18 — Findings are written at the next checkpoint at the latest
- Context: plan item 12 wanted gotchas written the moment they are found, which means extra tool calls mid-work; the user wants no context traffic during routine work.
- Decision: traps, decisions and questions go into `.context/` at the next checkpoint (commit, push, end) at the latest; long sessions may write important findings into the draft at once, because the draft survives compaction and the conversation may not.
- Rejected: immediate writes as a rule (token cost), end-only writes (lost on compaction or an aborted session).
- By: realfamousbae/claude-opus-5-5, T-20261022-rf-14
- Status: active
