# Phase 1: templates exist in every language with identical anchors; kit files are English.
. "$(dirname "$0")/lib.sh"

T="$KIT_DIR/template"
anchors() { awk '{ while (match($0, /<!-- ctx:[a-z-]+ -->/)) { print substr($0, RSTART, RLENGTH); $0 = substr($0, RSTART + RLENGTH) } }' "$1"; }

for f in MAP.md DECISIONS.md GOTCHAS.md TASKS.md QUESTIONS.md templates/entry.md; do
	for lang in en ru; do
		if [ -f "$T/i18n/$lang/$f" ]; then ok "$lang/$f exists"; else not_ok "$lang/$f exists"; fi
	done
	equals "$f: same anchors in en and ru" "$(anchors "$T/i18n/ru/$f")" "$(anchors "$T/i18n/en/$f")"
done

entry=$(cat "$T/i18n/en/templates/entry.md")
for key in "done" learned decisions verified risks next for-others for-humans files; do
	contains "entry has anchor $key" "$entry" "<!-- ctx:$key -->"
done
for ph in date author agent model tasks; do
	contains "entry has placeholder $ph" "$entry" "{{$ph}}"
done

block=$(cat "$KIT_DIR/snippets/agents-block.md")
contains "agents block begins with marker" "$(head -n 1 "$KIT_DIR/snippets/agents-block.md")" "<!-- ctx:begin v"
contains "agents block ends with marker" "$(tail -n 1 "$KIT_DIR/snippets/agents-block.md")" "<!-- ctx:end -->"
contains "agents block names Windows wrapper" "$block" 'ctx.cmd brief'

# Kit-owned files are English: no Cyrillic outside i18n/ru and tests.
has_cyr() { find "$@" -type f | while IFS= read -r f; do LC_ALL=C awk '/[\320\321]/ { print FILENAME; exit }' "$f"; done; }
# migrate.sh is the exception: it recognises Russian headings of legacy journals and writes Russian markers.
equals "no Cyrillic in kit-owned files" "$(has_cyr "$KIT_DIR/template/.context" "$KIT_DIR/snippets" | grep -v '/cmd/migrate.sh$')" ""
contains "Cyrillic detector works" "$(has_cyr "$KIT_DIR/template/i18n/ru")" "MAP.md"

# kit.json is flat: one "key": value per line (ctx config relies on it).
bad=$(awk 'NR > 1 && !/^}$/ && !/^  "[a-z_]+": ("[^"]*"|[0-9]+|true|false),?$/' "$T/.context/kit.json")
equals "kit.json is flat" "$bad" ""

finish
