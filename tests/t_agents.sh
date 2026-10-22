# Phase 5: the exact hook commands installed for Claude Code and Codex, fed with hook JSON on stdin.
. "$(dirname "$0")/lib.sh"
command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || { ok "skipped: no python to read hook JSON"; finish; exit $?; }
R="$T_TMP/r"; mkrepo "$R"; install_kit "$R" >/dev/null 2>&1
commit_all "$R" "install [no-ctx]"
CS="$R/.claude/settings.json"; CX="$R/.codex/hooks.json"
# On Windows Claude Code passes a native path (C:\Users\…) and runs the hook in Git Bash.
PD=$R; is_windows && PD=$(cygpath -w "$R")
check "Codex hooks file installed" test -f "$CX"
check "Codex hooks file is valid JSON" json_ok "$CX"

# Claude Code: SessionStart (startup) — plain text, within the 10,000-character hook cap
i=0; while [ $i -lt 400 ]; do printf -- '- module %s: lorem ipsum dolor sit amet, consectetur adipiscing\n' $i; i=$((i + 1)); done >> "$R/.context/MAP.md"
start=$(hook_cmd "$CS" SessionStart 0)
contains "Claude startup hook uses CLAUDE_PROJECT_DIR" "$start" '${CLAUDE_PROJECT_DIR}'
out=$(cd "$R" && printf '{"session_id":"s1","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$R" |
	CLAUDE_PROJECT_DIR="$PD" CTX_AGENT=claude sh -c "$start")
contains "startup brief printed" "$out" "# ctx brief"
size=$(printf '%s' "$out" | wc -c | tr -d ' ')
[ "$size" -le 10000 ] && ok "startup brief fits the 10,000-char hook cap ($size bytes)" || not_ok "brief fits hook cap" "$size bytes"
contains "points to the full brief" "$out" "Full brief: sh .context/bin/ctx brief"

# Claude Code: SessionStart (compact) — short brief with the draft
(cd "$R" && CTX_AGENT=claude "$CTX_SHELL" .context/bin/ctx entry --model m >/dev/null 2>&1)
d=$(ctx "$R" entry --path --agent claude); printf -- '- remember: the flaky test is timing\n' >> "$R/$d"
comp=$(hook_cmd "$CS" SessionStart 1)
out=$(cd "$R" && printf '{"session_id":"s1","cwd":"%s","source":"compact"}' "$R" | CLAUDE_PROJECT_DIR="$PD" CTX_AGENT=claude sh -c "$comp")
contains "after compaction the draft is back" "$out" "the flaky test is timing"
not_contains "after compaction no map" "$out" "lorem ipsum"

# Worktree: CLAUDE_PROJECT_DIR stays at the main checkout, the hook follows "cwd"
git -C "$R" add -A; git -C "$R" commit -q -m "wip [no-ctx]"
git -C "$R" worktree add -q -b feature "$T_TMP/wt" 2>/dev/null
out=$(cd "$R" && printf '{"session_id":"s2","cwd":"%s","source":"startup"}' "$T_TMP/wt" | CLAUDE_PROJECT_DIR="$PD" CTX_AGENT=claude sh -c "$start")
contains "worktree: brief is about the worktree's branch" "$out" "branch feature"

# Claude Code: Stop — reminder once, exit 2, stderr goes to Claude
stop=$(hook_cmd "$CS" Stop 0)
echo x > "$R/code.py"
rm -f "$R/$d"
out=$(cd "$R" && printf '{"session_id":"s3","cwd":"%s","stop_hook_active":false}' "$R" | CLAUDE_PROJECT_DIR="$PD" CTX_AGENT=claude sh -c "$stop" 2>&1); rc=$?
equals "Stop: reminder exits 2" "$rc" "2"
contains "Stop: reminder text" "$out" "no journal draft"
out=$(cd "$R" && printf '{"session_id":"s3","cwd":"%s","stop_hook_active":false}' "$R" | CLAUDE_PROJECT_DIR="$PD" CTX_AGENT=claude sh -c "$stop" 2>&1); rc=$?
equals "Stop: once per session" "$rc" "0"
out=$(cd "$R" && printf '{"session_id":"s4","cwd":"%s","stop_hook_active":true}' "$R" | CLAUDE_PROJECT_DIR="$PD" CTX_AGENT=claude sh -c "$stop" 2>&1); rc=$?
equals "Stop: stop_hook_active never blocks" "$rc" "0"
out=$(cd "$R" && CLAUDE_PROJECT_DIR="$PD" CTX_AGENT=claude sh -c "$stop" < /dev/null 2>&1); rc=$?
equals "Stop: no hook input never blocks" "$rc" "0"

# Codex: SessionStart from a subdirectory — JSON with additionalContext
mkdir -p "$R/src/deep"
cstart=$(hook_cmd "$CX" SessionStart 0)
out=$(cd "$R/src/deep" && printf '{"session_id":"c1","cwd":"%s","source":"startup","model":"m"}' "$R/src/deep" | sh -c "$cstart")
printf '%s' "$out" > "$T_TMP/codex.json"
check "Codex SessionStart output is JSON" json_ok "$T_TMP/codex.json"
contains "Codex SessionStart additionalContext" "$out" '"additionalContext":"# ctx brief'
contains "Codex brief knows it is codex" "$out" "/codex"
# Codex: Stop — always exit 0 with JSON: a block decision once, then {}
cstop=$(hook_cmd "$CX" Stop 0)
out=$(cd "$R" && printf '{"session_id":"c2","cwd":"%s","stop_hook_active":false,"turn_id":"t"}' "$R" | sh -c "$cstop" 2>/dev/null); rc=$?
equals "Codex Stop: reminder exits 0" "$rc" "0"
contains "Codex Stop: reminder is a block decision" "$out" '{"decision":"block","reason":"ctx reminder'
printf '%s' "$out" > "$T_TMP/stop.json"; check "Codex Stop: valid JSON" json_ok "$T_TMP/stop.json"
out=$(cd "$R" && printf '{"session_id":"c2","cwd":"%s","stop_hook_active":false,"turn_id":"t"}' "$R" | sh -c "$cstop" 2>/dev/null); rc=$?
equals "Codex Stop: then exit 0" "$rc" "0"
equals "Codex Stop: prints {} on exit 0" "$out" "{}"
contains "Codex Windows command uses ctx.ps1" "$(hook_cmd "$CX" Stop 0 commandWindows)" "ctx.ps1"

# Re-install keeps both files unchanged; uninstall removes .codex/hooks.json we created
before=$(snapshot "$R"); install_kit "$R" >/dev/null 2>&1
equals "re-install: no change" "$(snapshot "$R")" "$before"
install_kit "$R" --uninstall >/dev/null 2>&1
check "uninstall removes our Codex hooks file" test ! -f "$CX"

finish
