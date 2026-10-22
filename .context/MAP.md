# Project map

<!-- What an agent needs to find its way around. Short, factual. Update when structure, commands or environment change. -->

## Modules <!-- ctx:modules -->
- `install.sh` — the installer (POSIX sh): install / `--update` / `--uninstall` / `--ci` / `--migrate`; merges `.claude/settings.json` and `.codex/hooks.json` with jq → python → printed fragment. `install.ps1` finds Git Bash and calls it.
- `template/.context/` — what lands in a project's `.context/`: `PROTOCOL.md`, `kit.json`, `bin/ctx` (dispatcher), `bin/ctx-lib.sh` (shared functions), `bin/cmd/*.sh` (one file per subcommand), `bin/ctx.cmd` / `bin/ctx.ps1` (Windows wrappers).
- `template/i18n/<lang>/` — record templates (MAP, DECISIONS, GOTCHAS, TASKS, QUESTIONS, `templates/entry.md`); same `<!-- ctx:… -->` anchors in every language.
- `template/.githooks/`, `template/.claude/`, `template/.codex/`, `template/.github/workflows/ctx.yml` — hooks and agent integration copied into projects.
- `snippets/` — the AGENTS.md block and the `.gitattributes` block (inserted between markers).
- `tests/` — `t_*.sh` on temporary git repos, `lib.sh` helpers, `fixtures/legacy-journal/` (synthetic), `windows/wrappers.ps1`.
- `docs/agents.md` — what the kit relies on in Claude Code and Codex, with sources.
- This repository dogfoods the kit: `.context/`, `.githooks/`, `.claude/`, `.codex/`, `AGENTS.md`, `CLAUDE.md` are an installed copy. `.context/bin/` is a COPY of `template/.context/bin/` — edit the template, then `sh install.sh --update`.

## Entry points <!-- ctx:entry-points -->
- Users: one phrase to an agent → `BOOTSTRAP.md` → `install.sh`. Migration: `MIGRATION.md`.
- Runtime: `.context/bin/ctx <command>` → `exec sh bin/cmd/<command>.sh` (shell overridable with `CTX_SHELL`).

## Build, run, test <!-- ctx:commands -->
- All tests: `sh tests/run.sh`; one file: `sh tests/run.sh t_brief`; under dash: `TEST_SH=dash sh tests/run.sh`.
- Lint: `shellcheck -S warning -s sh -x <files>` (`.shellcheckrc` allows `local`).
- CI: `.github/workflows/test.yml` — ubuntu (dash + bash), macos (bash 3.2), windows (Git Bash, PowerShell 5.1/7, cmd), shellcheck. Watch with `gh run watch`.
- Refresh the dogfood copy after editing `template/`: `sh install.sh --update`.

## Environment <!-- ctx:environment -->
- Needs only git + POSIX sh/awk/sed. jq and python are optional (settings merge, one test helper).
- `claude` and `codex` CLIs are useful for manual end-to-end checks (`claude -p …`, `codex exec -s read-only --dangerously-bypass-hook-trust …` in a throwaway repo).
