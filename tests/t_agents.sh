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
[ "$size" -le 2500 ] && ok "startup card is small ($size bytes; Claude Code caps hook context at 10,000 chars)" || not_ok "startup card is small" "$size bytes"
contains "the card points to the full brief" "$out" "ctx brief --full"

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

# No Stop hook any more: nothing runs per turn
check "no Stop hook in Claude settings" sh -c "! grep -q '\"Stop\"' '$CS'"
check "no Stop hook in Codex hooks" sh -c "! grep -q '\"Stop\"' '$CX'"

# Claude Code: PreToolUse checkpoint — "if" filters make it run only for push/deploy-like commands
pre=$(hook_cmd "$CS" PreToolUse 0)
contains "first handler is filtered to git push" "$(hook_cmd "$CS" PreToolUse 0 if)" "Bash(git push"
pj() { printf '{"session_id":"s5","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$R" "$1"; }
out=$(cd "$R" && pj "git push origin main" | CLAUDE_PROJECT_DIR="$PD" CTX_AGENT=claude sh -c "$pre"); rc=$?
equals "push gate exits 0" "$rc" "0"
contains "push gate asks the user while the goal is not met" "$out" '"permissionDecision":"ask"'
not_contains "push gate never says allow" "$out" '"allow"'
printf '%s' "$out" > "$T_TMP/ask.json"; check "push gate output is JSON" json_ok "$T_TMP/ask.json"
equals "ordinary command: no output" "$(cd "$R" && pj "npm test" | CLAUDE_PROJECT_DIR="$PD" CTX_AGENT=claude sh -c "$pre")" ""
equals "reading a deploy file: no output" "$(cd "$R" && pj "cat deploy.md" | CLAUDE_PROJECT_DIR="$PD" CTX_AGENT=claude sh -c "$pre")" ""
equals "CTX_CONFIRMED=1 passes" "$(cd "$R" && pj "CTX_CONFIRMED=1 git push" | CLAUDE_PROJECT_DIR="$PD" CTX_AGENT=claude sh -c "$pre")" ""

# Codex: SessionStart from a subdirectory — JSON with additionalContext
mkdir -p "$R/src/deep"
cstart=$(hook_cmd "$CX" SessionStart 0)
out=$(cd "$R/src/deep" && printf '{"session_id":"c1","cwd":"%s","source":"startup","model":"m"}' "$R/src/deep" | sh -c "$cstart")
printf '%s' "$out" > "$T_TMP/codex.json"
check "Codex SessionStart output is JSON" json_ok "$T_TMP/codex.json"
contains "Codex SessionStart additionalContext" "$out" '"additionalContext":"# ctx brief'
contains "Codex brief knows it is codex" "$out" "/codex"
# Codex: PreToolUse checkpoint — deny with the card while the goal is not met (Codex has no "ask")
cpre=$(hook_cmd "$CX" PreToolUse 0)
out=$(cd "$R" && pj "./scripts/deploy.sh prod" | sh -c "$cpre"); rc=$?
equals "Codex gate exits 0" "$rc" "0"
contains "Codex gate denies with the card" "$out" '"permissionDecision":"deny"'
contains "Codex gate explains the way out" "$out" "CTX_CONFIRMED=1"
printf '%s' "$out" > "$T_TMP/deny.json"; check "Codex gate output is JSON" json_ok "$T_TMP/deny.json"
equals "Codex: ordinary command silent" "$(cd "$R" && pj "ls -la" | sh -c "$cpre")" ""
# once the session is finished with outcome met, the gates are silent
(cd "$R" && CTX_AGENT=codex "$CTX_SHELL" .context/bin/ctx start --goal "ship the export" >/dev/null 2>&1)
fill_draft "$R" codex >/dev/null
(cd "$R" && CTX_AGENT=codex "$CTX_SHELL" .context/bin/ctx end --outcome met >/dev/null 2>&1)
equals "Codex gate silent after outcome met" "$(cd "$R" && pj "git push" | sh -c "$cpre")" ""
contains "Codex Windows command uses ctx.ps1" "$(hook_cmd "$CX" PreToolUse 0 commandWindows)" "ctx.ps1"

# Re-install keeps both files unchanged; uninstall removes .codex/hooks.json we created
before=$(snapshot "$R"); install_kit "$R" >/dev/null 2>&1
equals "re-install: no change" "$(snapshot "$R")" "$before"
install_kit "$R" --uninstall >/dev/null 2>&1
check "uninstall removes our Codex hooks file" test ! -f "$CX"

finish
