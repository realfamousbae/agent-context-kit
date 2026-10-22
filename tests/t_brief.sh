# Phase 2: ctx brief — priority, budget, never fails.
. "$(dirname "$0")/lib.sh"
today=$(date +%Y%m%d)

# never fails: outside a repo, without .context, with broken kit.json, with an unreachable remote
mkdir -p "$T_TMP/plain"
out=$(cd "$T_TMP/plain" && "$CTX_SHELL" "$KIT_DIR/template/.context/bin/ctx" brief); rc=$?
equals "outside a repo: exit 0" "$rc" "0"
contains "outside a repo: says so" "$out" "not inside a git repository"

R="$T_TMP/r"; mkrepo "$R"
mkdir -p "$R/.context/bin"; cp -R "$KIT_DIR/template/.context/bin/." "$R/.context/bin/"
rmdir "$R/.context" 2>/dev/null
out=$(ctx "$R" brief); rc=$?
equals "partial .context: exit 0" "$rc" "0"

rm -rf "$R/.context"; kit_copy "$R"
ctx "$R" config push_claims never >/dev/null
printf 'garbage{' > "$R/.context/kit.json"
out=$(ctx "$R" brief); rc=$?
equals "corrupt kit.json: exit 0" "$rc" "0"
contains "corrupt kit.json: warning" "$out" "kit.json is missing or unreadable"
cp "$KIT_DIR/template/.context/kit.json" "$R/.context/kit.json"
ctx "$R" config push_claims never >/dev/null

git -C "$R" remote add origin "$T_TMP/does-not-exist.git"
out=$(CTX_NO_FETCH=0 ctx "$R" brief); rc=$?
equals "unreachable remote: exit 0" "$rc" "0"
contains "unreachable remote: warning" "$out" "Could not fetch origin"
git -C "$R" remote remove origin

if ! is_windows && [ "$(id -u)" != 0 ]; then
	chmod -R a-w "$R/.git"
	out=$(ctx "$R" brief); rc=$?
	chmod -R u+w "$R/.git"
	equals "read-only .git: exit 0" "$rc" "0"
	contains "read-only .git: still prints tasks header" "$out" "# ctx brief"
	# a read-only sandbox (Codex -s read-only): nothing is writable, not even the temp dir
	chmod -R a-w "$R"
	out=$(TMPDIR="$T_TMP/no-such-dir" ctx "$R" brief); rc=$?
	chmod -R u+w "$R"
	equals "read-only sandbox: exit 0" "$rc" "0"
	contains "read-only sandbox: brief still printed" "$out" "# ctx brief"
else
	ok "read-only .git: skipped on this platform"
fi

# content and priority
printf -- '- G-%s-bb-1 · active trap — workaround (bob/codex)\n- G-%s-bb-2 · old trap [resolved 2026-01-01] fixed\n' "$today" "$today" >> "$R/.context/GOTCHAS.md"
printf '\n### D-%s-bb-1 — Keep it\n- Status: active\n\n### D-%s-bb-2 — Drop it\n- Status: superseded by D-%s-bb-1\n' "$today" "$today" "$today" >> "$R/.context/DECISIONS.md"
printf '\n## Modules <!-- ctx:modules -->\n- `src/` — the app\n' >> "$R/.context/MAP.md"
commit_all "$R" "setup"
ctx "$R" claim --new "Upload" --area "src/" >/dev/null
git -C "$R" config ctx.author bob; git -C "$R" config ctx.initials bb
(CTX_AGENT=codex ctx "$R" entry --model m1 >/dev/null 2>&1); fill_draft "$R" codex >/dev/null
ctx "$R" ask @alice "Why src?" >/dev/null
ctx "$R" ask @codex "For any codex" >/dev/null
commit_all "$R" "bob work"
echo x > "$R/code.py"; git -C "$R" add code.py; git -C "$R" commit -q -m "hotfix by a human"
git -C "$R" config ctx.author alice; git -C "$R" config ctx.initials aa

out=$(CTX_AGENT=claude ctx "$R" brief --full)
contains "question for me" "$out" "Why src?"
not_contains "question for codex is not mine (I am claude)" "$out" "For any codex"
contains "count of other questions" "$out" "1 other open question"
contains "my claim" "$out" "(yours)"
contains "active gotcha" "$out" "active trap"
not_contains "resolved gotcha hidden" "$out" "old trap"
contains "others' entry" "$out" "bob/codex, m1"
contains "commit without journal" "$out" "hotfix by a human [code.py]"
contains "active decision" "$out" "Keep it"
not_contains "superseded decision hidden" "$out" "Drop it"
contains "map" "$out" "the app"
order=$(printf '%s\n' "$out" | grep -n -e '^## Open questions' -e '^## Tasks' -e '^## Gotchas' -e '^## New from others' -e '^## Commits' -e '^## Decisions' -e '^## Project map' | sed 's/^[0-9]*://' | tr '\n' '|')
equals "sections in priority order" "$order" "## Open questions for you — answer: ctx ask --answer Q-… \"…\"|## Tasks in progress — claim yours before editing: ctx claim T-… --area \"…\"|## Gotchas (active)|## New from others since your last entry|## Commits with code but no journal entry (ask their authors or check the diff)|## Decisions (active; full text in .context/DECISIONS.md)|## Project map|"

# budget
small=$(CTX_AGENT=claude ctx "$R" brief --full --budget 700)
size=$(printf '%s' "$small" | wc -c | tr -d ' ')
[ "$size" -le 900 ] && ok "budget 700 respected ($size bytes)" || not_ok "budget 700 respected" "$size bytes"
contains "budget: questions survive" "$small" "Why src?"
contains "budget: omitted sections named" "$small" "Omitted to fit the brief budget: Tasks in progress"
contains "budget: over-budget warning" "$small" "over the 700-byte brief budget"

# --short: draft is shown
(CTX_AGENT=claude ctx "$R" entry --model m2 >/dev/null 2>&1)
d=$(ctx "$R" entry --path --agent claude)
printf '%s\n' "- found a thing" >> "$R/$d"
short=$(CTX_AGENT=claude ctx "$R" brief --short)
contains "short: draft shown" "$short" "Your journal draft: $d"
contains "short: draft content" "$short" "found a thing"
not_contains "short: no map" "$short" "the app"

# many entries → compaction warning
ctx "$R" config compact_threshold_entries 1 >/dev/null
contains "compaction warning" "$(ctx "$R" brief)" "time to compact"

# start card (default): small, one line per entry of others, counts instead of long sections
ctx "$R" config compact_threshold_entries 30 >/dev/null
card=$(CTX_AGENT=claude ctx "$R" brief)
size=$(printf '%s' "$card" | wc -c | tr -d ' ')
[ "$size" -le 2500 ] && ok "card within start_budget_bytes ($size bytes)" || not_ok "card within budget" "$size"
contains "card: question for me" "$card" "Why src?"
contains "card: claims" "$card" "## Claims"
contains "card: one line per entry of others" "$card" "- bob/codex: did a thing"
not_contains "card: no entry headers" "$card" "### "
contains "card: new gotcha" "$card" "active trap"
contains "card: commits without journal only counted" "$card" "code commit(s) without a journal entry"
not_contains "card: no map" "$card" "the app"
not_contains "card: no decisions" "$card" "Keep it"
contains "card: footer" "$card" "ctx start --goal"
resume=$(cd "$R" && printf '{"source":"resume","cwd":"%s"}' "$R" | CTX_AGENT=claude "$CTX_SHELL" .context/bin/ctx brief --hook)
contains "resume: questions again" "$resume" "Why src?"
not_contains "resume: no claims or entries (already in the transcript)" "$resume" "## Claims"

finish
