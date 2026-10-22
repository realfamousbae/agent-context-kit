#!/bin/sh
# shellcheck source=../ctx-lib.sh
CTX_BIN=${CTX_BIN:-$(cd "$(dirname "$0")/.." && pwd)}
. "$CTX_BIN/ctx-lib.sh"
# ctx migrate PATH… — mechanical half of MIGRATION.md: move a legacy agent journal into
# .context/journal/archive/legacy/ (history kept via git mv) and copy bullet items from recognisable
# sections into GOTCHAS, DECISIONS, TASKS and QUESTIONS, marked as restored. The agent then reviews them,
# writes journal/archive/SUMMARY-legacy.md and replaces the old journal rules in AGENTS.md.
ctx_init
[ $# -gt 0 ] || ctx_die "usage: ctx migrate PATH… (legacy journal files or directories)"
dest=.context/journal/archive/legacy
mkdir -p "$dest" || ctx_die "cannot create $dest"
case $(ctx_lang) in
	ru) mark="(восстановлено из старого журнала, проверить)"; ctxl="Контекст"; decl="Решение"; byl="Автор" ;;
	*) mark="(restored from the legacy journal, verify)"; ctxl="Context"; decl="Decision"; byl="By" ;;
esac
me=$(ctx_author)

moved=""
for p in "$@"; do
	p=${p%/}
	[ -e "$p" ] || ctx_die "no such path: $p"
	target="$dest/$(basename "$p")"
	[ -e "$target" ] && ctx_die "$target already exists"
	if git ls-files --error-unmatch "$p" >/dev/null 2>&1 || [ -n "$(git ls-files "$p" 2>/dev/null)" ]; then
		git mv "$p" "$target" || ctx_die "git mv $p failed"
	else
		mv "$p" "$target" || ctx_die "mv $p failed"
	fi
	moved="$moved $target"
done

# category TAB text, from bullets under recognised headings.
items=$(find $moved -type f -name '*.md' 2>/dev/null | sort | while IFS= read -r f; do
	awk -v src="$(basename "$f")" '
		/^#/ {
			h = tolower($0); cat = ""
			if (h ~ /gotcha|pitfall|trap|caveat|(Л|л)овушк|(Г|г)рабл|(П|п)одводн/) cat = "gotcha"
			else if (h ~ /decision|(Р|р)ешени/) cat = "decision"
			else if (h ~ /question|(В|в)опрос/) cat = "question"
			else if (h ~ /in progress|current|now|doing|(В|в) работе|(С|с)ейчас|(Т|т)екущ/) cat = "now"
			else if (h ~ /idea|todo|next|backlog|future|later|(И|и)де|(П|п)лан|(Д|д)альше|(П|п)отом|(Б|б)эклог/) cat = "next"
			next
		}
		cat != "" && /^[-*] / {
			t = substr($0, 3); sub(/^\[[ ]\] /, "", t); sub(/[ \t\r]+$/, "", t)
			if (t ~ /^\[[xX]\]/ || index(t, "✅")) next
			if (t != "") print cat "\t" t "\t" src
		}' "$f"
done)

tmp=$(ctx_tmp) || ctx_die "cannot create a temp file"
printf '%s\n' "$items" > "$tmp"
n=0
while IFS='	' read -r cat text src; do
	[ -n "$cat" ] || continue
	case $cat in
		gotcha) printf -- '- %s · %s %s\n' "$(ctx_next_id G)" "$text" "$mark" >> .context/GOTCHAS.md ;;
		decision)
			printf '\n### %s — %s\n- %s: %s %s\n- %s: %s\n- %s: %s/legacy\n- Status: active\n' \
				"$(ctx_next_id D)" "$text" "$ctxl" "$src" "$mark" "$decl" "$text" "$byl" "$me" >> .context/DECISIONS.md ;;
		question)
			who=@all
			case $text in @*) who=$(printf '%s' "$text" | sed 's/^\(@[A-Za-z0-9_-]*\).*/\1/' | tr 'A-Z' 'a-z')
				text=$(printf '%s' "$text" | sed 's/^@[A-Za-z0-9_-]*[:,]* *//') ;; esac
			"${CTX_SHELL:-sh}" "$CTX_BIN/cmd/ask.sh" "$who" "$text $mark" >/dev/null 2>&1 ||
				printf -- '- %s · %s · from %s/legacy · %s %s\n' "$(ctx_next_id Q)" "$who" "$me" "$text" "$mark" >> .context/QUESTIONS.md ;;
		now|next)
			id=$(ctx_next_id T)
			ttmp=$(ctx_tmp) || continue
			awk -v nl="- [ ] $id $text $mark" -v sec="<!-- ctx:$cat -->" '
				{ l[++n] = $0 }
				END {
					h = 0; e = n + 1
					for (i = 1; i <= n; i++) if (l[i] ~ /^##[^#]/) { if (h) { e = i; break } if (index(l[i], sec)) h = i }
					at = h; for (i = h + 1; i < e; i++) if (l[i] !~ /^[ \t\r]*$/) at = i
					for (i = 1; i <= n; i++) { print l[i]; if (i == at) print nl }
					if (!h) print nl
				}' .context/TASKS.md > "$ttmp" && cat "$ttmp" > .context/TASKS.md
			rm -f "$ttmp" ;;
	esac
	n=$((n + 1))
done < "$tmp"
rm -f "$tmp"

ctx_say "Moved to $dest:$moved"
ctx_say "Restored $n item(s): $(printf '%s\n' "$items" | awk -F '\t' 'NF { c[$1]++ } END { for (k in c) printf "%s %d  ", k, c[k] }')"
ctx_say "Next (MIGRATION.md): review the restored items, write .context/journal/archive/SUMMARY-legacy.md (~2 KB),"
ctx_say "replace the old journal rules in AGENTS.md (keep other project rules), ask @all that the old journal is retired,"
ctx_say "and commit the migration separately with its own journal entry."
exit 0
