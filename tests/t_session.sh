# v0.2 session flow: ctx start (goal + claim) → work → commit (outcome in-progress) → ctx end → outcome.
. "$(dirname "$0")/lib.sh"
R="$T_TMP/r"; mkrepo "$R"; install_kit "$R" >/dev/null 2>&1
ctx "$R" config push_claims never >/dev/null
commit_all "$R" "install [no-ctx]"
export CTX_AGENT=claude

out=$(ctx "$R" start --goal "Add CSV export; done when export_csv() writes a file and tests pass" --plan "parser, writer, tests" --area "src/export/ tests/" --model m 2>&1)
contains "start: claim made" "$out" "Claimed T-"
contains "start: draft announced" "$out" "Journal draft:"
d=$(ctx "$R" entry --path --agent claude)
contains "goal written into the draft" "$(cat "$R/$d")" "- Add CSV export; done when export_csv() writes a file"
contains "plan written into the draft" "$(cat "$R/$d")" "- parser, writer, tests"
contains "claim title from the goal" "$(cat "$R/.context/TASKS.md")" "Add CSV export"

# checkpoint card: goal, changes outside the claimed area
mkdir -p "$R/src/export" "$R/docs"; echo x > "$R/src/export/csv.py"; echo y > "$R/docs/notes.md"
card=$(ctx "$R" checkpoint push)
contains "card shows the goal" "$card" "Add CSV export"
contains "card lists uncommitted files" "$card" "src/export/csv.py"
contains "card flags files outside the claim" "$card" "Outside your claimed area: docs/notes.md"
size=$(printf '%s' "$card" | wc -c | tr -d ' ')
[ "$size" -le 1500 ] && ok "card is short ($size bytes)" || not_ok "card is short" "$size"

# mid-session commit: the entry is finished with outcome in-progress — no premature verdict
fill_draft "$R" claude >/dev/null
equals "default outcome is in-progress" "$(awk '/^outcome:/ { print $2 }' "$R/$d")" "in-progress"
check "mid-session commit passes" commit_all "$R" "csv writer"

# exit checkpoint
out=$(ctx "$R" end)
contains "end without outcome shows the goal" "$out" "Add CSV export"
contains "end asks for a verdict" "$out" "ctx end --outcome met|partly|not-met"
out=$(ctx "$R" end --outcome partly)
equals "outcome recorded" "$(awk '/^outcome:/ { print $2 }' "$R/$d")" "partly"
contains "partly: claim paused, not done" "$(cat "$R/.context/TASKS.md")" "paused"
contains "partly: tell the user" "$out" "tell the user what is missing"
check_fails "end rejects a bad outcome" ctx "$R" end --outcome maybe

# a 0.1 entry (no Goal section) can still be finished
cp "$R/$d" "$T_TMP/old.md"
awk '!/ctx:goal|make the thing work|ctx:plan/' "$T_TMP/old.md" | sed 's/^status: done/status: draft/' > "$R/$d"
check "entry without Goal anchor finishes (0.1 compatibility)" ctx "$R" entry --finish --agent claude

# upgrade from 0.1: Stop hook removed, PreToolUse added, AGENTS block v1 replaced (not duplicated)
U="$T_TMP/u"; mkrepo "$U"; mkdir -p "$U/.claude" "$U/.codex"
cat > "$U/.claude/settings.json" <<'JSON'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"sh \"$CLAUDE_PROJECT_DIR/.context/bin/ctx\" check --soft"}]},{"hooks":[{"type":"command","command":"echo keep-me"}]}]}}
JSON
printf '<!-- ctx:begin v1 -->\nold block\n<!-- ctx:end -->\n\n# Rules\n' > "$U/AGENTS.md"
install_kit "$U" --update >/dev/null 2>&1
s=$(cat "$U/.claude/settings.json")
not_contains "upgrade: old Stop hook gone" "$s" "check --soft"
contains "upgrade: user Stop hook kept" "$s" "keep-me"
contains "upgrade: PreToolUse checkpoint added" "$s" "checkpoint --hook"
equals "upgrade: one ctx block" "$(grep -c 'ctx:begin' "$U/AGENTS.md")" "1"
contains "upgrade: block is v2" "$(head -n 1 "$U/AGENTS.md")" "ctx:begin v2"
contains "upgrade: user rules kept" "$(cat "$U/AGENTS.md")" "# Rules"

finish
