# Gotchas

<!-- One line per trap, append only, written the moment it is found: -->
<!-- - G-YYYYMMDD-ii-n · what happens — workaround (author/agent, T-…) -->
<!-- Obsolete: add "[resolved YYYY-MM-DD] reason" to the line, never delete it. -->
- G-20261022-rf-1 · bash 3.2 (macOS /bin/sh) fails to parse `case … in pattern)` inside `$( … )` — write `(pattern)` with the leading parenthesis in any case that can end up in a command substitution (realfamousbae/claude)
- G-20261022-rf-2 · gawk counts characters in UTF-8 locales, mawk/BWK awk count bytes: `substr`/`RSTART` around `·`, `—`, Cyrillic drift between Ubuntu and macOS — ctx-lib sets `LC_ALL=C`; keep offsets on ASCII anchors (realfamousbae/claude)
- G-20261022-rf-3 · Git Bash rewrites arguments like `origin/main:.context/TASKS.md` into Windows path lists when calling git.exe — ctx disables it via `MSYS2_ARG_CONV_EXCL='*'`; in tests wrap only that call, other test args are /tmp paths that need conversion (realfamousbae/claude)
- G-20261022-rf-4 · MSYS gawk reads files in text mode and drops CR, so an awk-based CR counter always says 0 on Windows — count with `tr -dc '\r' | wc -c` (realfamousbae/claude)
- G-20261022-rf-5 · Windows PowerShell 5.1 with `$ErrorActionPreference='Stop'` turns any stderr line of a native command into a terminating error — ctx.ps1/install.ps1 switch to 'Continue' before calling bash (realfamousbae/claude)
- G-20261022-rf-6 · `powershell -Command "& script.ps1"` returns 1, not the script's exit code (2 becomes 1) — Codex Stop uses JSON decisions with exit 0 instead of exit 2 (realfamousbae/claude)
- G-20261022-rf-7 · In POSIX sh `VAR=x some_function` keeps VAR set after the call (bash in sh mode) — in tests wrap such calls in `( … )`, otherwise e.g. `CTX_INSTALL_NO_JQ` leaks into later checks (realfamousbae/claude)
- G-20261022-rf-8 · jq: `A + B as $x | …` binds as `A + (B as $x | …)` — parenthesise `(A + B) as $x` (realfamousbae/claude)
- G-20261022-rf-9 · `.context/bin/` in this repo is an installed copy of `template/.context/bin/` — editing only one of them silently diverges; edit the template and run `sh install.sh --update` (realfamousbae/claude)
- G-20261022-rf-10 · The PROTOCOL.md example `T-20261022-aa-1` once matched "today" and shifted `ctx id` — ctx_next_id skips PROTOCOL.md, bin/ and templates/; keep examples out of record files (realfamousbae/claude)
- G-20261022-rf-11 · `codex exec` 0.163 did not run the project SessionStart hook from .codex/hooks.json (even with --dangerously-bypass-hook-trust and the project trusted via -c); Codex read the context only because AGENTS.md says to run ctx brief — keep AGENTS.md as the primary path for Codex (realfamousbae/claude, T-20261022-rf-9) [resolved 2026-10-22] wrong diagnosis: the test project was not trusted, see G-20261022-rf-12
- G-20261022-rf-13 · Codex loads a project's `.codex/` (config.toml and hooks.json) only when the project is trusted. In codex 0.163 `-c 'projects."/abs/path".trust_level="trusted"'` did NOT trust it; `-c projects./abs/path.trust_level=trusted` (unquoted, path without dots) did. Check with a hook that writes a marker file, or look for `hooks.additional_context` in ~/.codex/sessions/*.jsonl (realfamousbae/claude, T-20261022-rf-9)
- G-20261022-rf-14 · Two journal entries of one author+agent in the same minute: the second gets `HHMMSSZ`, which sorts BEFORE `HHMMZ` ("0" < "Z"), so "newest entry" logic sees them swapped — harmless in real sessions, visible in scripted benchmarks (realfamousbae/claude, T-20261022-rf-14)
