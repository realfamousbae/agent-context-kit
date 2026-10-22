---
date: 2026-10-22 19:58 +03:00
author: realfamousbae
agent: claude
model: claude-opus-5-5
tasks: [T-20261022-rf-15]
status: done
outcome: met
---
## Goal <!-- ctx:goal -->
- Fix frictions found in a live Codex run: --help for every command, ctx start --no-commit, claim titles cut at a word boundary; done when tests cover them and CI is green

## Done <!-- ctx:done -->
- Walked the Codex guide end to end with `codex exec` 0.163 in a throwaway repo (ru records): install from GitHub, BOOTSTRAP by Codex, a task, commit, push stopped by the checkpoint, confirmed push with CTX_CONFIRMED=1, `ctx end --outcome met`.
- Fixed what the run exposed: `ctx <cmd> --help`, `ctx start --no-commit`, claim titles cut at a word boundary.

## Learned (not in the code) <!-- ctx:learned -->
- Without `--help` Codex spent 4 tool calls reading ctx sources to learn `ctx end` syntax — usage text is cheaper than discovery.
- `ctx start --area` commits the claim; in workspace-write `.git` is read-only, and a user may say "do not commit" — hence `--no-commit`.
- `shell_environment_policy.set = { CTX_AGENT = "codex" }` (Codex config) makes Codex-run ctx commands sign as codex.
- Codex in workspace-write cannot commit at all (`.git/index.lock`); the user commits or approves an escalation.

## How it was verified <!-- ctx:verified -->
`sh tests/run.sh` and `TEST_SH=dash` (t_session covers --help, --no-commit, titles); live Codex run as described.

## Next step <!-- ctx:next -->
- Optionally let the installer write `.codex/config.toml` with CTX_AGENT so the Codex guide loses a manual step.

## Files touched <!-- ctx:files -->
- `template/.context/bin/ctx`, `cmd/start.sh`, `cmd/claim.sh`, `tests/t_session.sh`
