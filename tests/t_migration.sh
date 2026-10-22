# Phase 4: a legacy agent journal stops the installer; --migrate + ctx migrate move it into .context/.
. "$(dirname "$0")/lib.sh"
today=$(date +%Y%m%d)
R="$T_TMP/r"; mkrepo "$R"
cp "$KIT_DIR"/tests/fixtures/legacy-journal/*.md "$R/"
commit_all "$R" "legacy journal"

out=$(install_kit "$R" 2>&1); rc=$?
equals "installer stops on a legacy journal (exit 3)" "$rc" "3"
contains "names NOTES.md" "$out" "NOTES.md"
contains "names CHANGES.md" "$out" "CHANGES.md"
contains "names journal rules in AGENTS.md" "$out" "AGENTS.md (journal rules)"
contains "points to MIGRATION.md" "$out" "MIGRATION.md"
check "nothing installed" test ! -d "$R/.context"

check "--migrate installs" install_kit "$R" --migrate
contains "user AGENTS.md content kept" "$(cat "$R/AGENTS.md")" "Keep commits small and focused."
out=$(ctx "$R" migrate NOTES.md CHANGES.md 2>&1)
contains "migrate reports" "$out" "Restored"
check "NOTES.md moved with git mv" test -f "$R/.context/journal/archive/legacy/NOTES.md"
check "old NOTES.md gone" test ! -f "$R/NOTES.md"
equals "move is staged as a rename" "$(git -C "$R" status --porcelain | grep -c '^R ')" "2"

g=$(cat "$R/.context/GOTCHAS.md")
contains "gotcha 1 restored" "$g" "- G-$today-aa-1 · \`make test\` needs \`TZ=UTC\`, otherwise the date tests fail (restored from the legacy journal, verify)"
contains "gotcha 2 restored" "$g" "The demo API answers 200"
contains "in progress → Now" "$(sed -n '/ctx:now/,/ctx:next/p' "$R/.context/TASKS.md")" "Export to CSV (codex, \`src/export/\`)"
contains "ideas → Next" "$(sed -n '/ctx:next/,/ctx:blocked/p' "$R/.context/TASKS.md")" "Add a dark theme"
q=$(cat "$R/.context/QUESTIONS.md")
contains "open question → QUESTIONS with addressee" "$q" "· @codex · from alice/human · can we drop the legacy \`--fast\` flag?"
not_contains "answered question skipped" "$q" "cache still needed"
contains "decision → DECISIONS" "$(cat "$R/.context/DECISIONS.md")" "— Use SQLite for local storage"
contains "codex sees the question in its brief" "$(cd "$R" && CTX_AGENT=codex "$CTX_SHELL" .context/bin/ctx brief)" "can we drop the legacy"

# ru project: markers in Russian
U="$T_TMP/u"; mkrepo "$U"; cp "$KIT_DIR/tests/fixtures/legacy-journal/NOTES.md" "$U/"
commit_all "$U" "legacy"
install_kit "$U" --migrate --language ru >/dev/null 2>&1
ctx "$U" migrate NOTES.md >/dev/null 2>&1
contains "ru marker" "$(cat "$U/.context/GOTCHAS.md")" "(восстановлено из старого журнала, проверить)"

finish
