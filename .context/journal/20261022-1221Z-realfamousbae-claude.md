---
date: 2026-10-22 15:21 +03:00
author: realfamousbae
agent: claude
model: claude-opus-5-5
tasks: [T-20261022-rf-1]
status: done
---
## Done <!-- ctx:done -->
- Built phases 1–5 of the plan: protocol and en/ru templates, `ctx` scripts with Windows wrappers, git hooks, installer + BOOTSTRAP/MIGRATION, Claude Code and Codex hooks. CI matrix ubuntu/macos/windows is green.
- Installed the kit into its own repository (language en) and recorded the decisions and gotchas from the build.

## Learned (not in the code) <!-- ctx:learned -->
- Plan vs docs: Claude Code caps hook context at 10,000 chars (D-20261022-rf-2); PreCompact output never reaches the model (D-20261022-rf-3); Codex has hooks now, needs `/hooks` trust and JSON from Stop (D-20261022-rf-6); Codex sandboxes keep `.git` read-only and may forbid temp files (D-20261022-rf-7).
- CI on three OSes found five portability bugs no local run showed: G-20261022-rf-2, -3, -5, -6 and the bash 3.2 `case` parse bug (G-20261022-rf-1).
- A live `codex exec -s read-only` run exposed the empty brief (mktemp); now covered by a test with an unwritable tree and TMPDIR.
- Codex project hooks were not seen firing in `codex exec` (G-20261022-rf-11); AGENTS.md alone got Codex to run the brief.
- BOOTSTRAP commands: `$TMPDIR` is usually unset on Linux and Windows PowerShell blocks `& install.ps1` by default — now `mktemp -d` and `-ExecutionPolicy Bypass -File`.

## Decisions <!-- ctx:decisions -->
- D-20261022-rf-1 … D-20261022-rf-13

## How it was verified <!-- ctx:verified -->
`sh tests/run.sh` and `TEST_SH=dash sh tests/run.sh` (11 files, ~340 checks); GitHub Actions on ubuntu, macos, windows incl. PowerShell 5.1/7 and cmd wrappers; shellcheck. Manual: `claude -p` and `codex exec` in a throwaway repo retold the context from hooks / AGENTS.md. Not verified: Codex hooks inside a real Windows Codex session; Claude Code on Windows end to end.

## Unfinished / risks <!-- ctx:risks -->
- `.context/bin` here is a copy of `template/.context/bin`; t_templates now fails on drift, but only in this repo.
- `install.sh` uses `local` (fine in every target shell, not strict POSIX).

## Next step <!-- ctx:next -->
- Pilot (T-20261022-rf-7): install into a real two-person project; each participant runs the installer and approves `.codex/hooks.json` with `/hooks`.

## For humans (what the agent could not do) <!-- ctx:for-humans -->
- @realfamousbae: pick the pilot project and the second participant; Codex hook trust (`/hooks`) and Claude Code folder trust must be approved by a human.

## Files touched <!-- ctx:files -->
- `install.sh`, `install.ps1`, `template/**`, `snippets/*`, `tests/**`, `docs/agents.md`, `README.md`, `BOOTSTRAP.md`, `MIGRATION.md`, `.github/workflows/*`, dogfood copy (`.context/`, `.githooks/`, `.claude/`, `.codex/`, `AGENTS.md`, `CLAUDE.md`)
