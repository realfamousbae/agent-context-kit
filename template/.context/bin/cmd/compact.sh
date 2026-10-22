#!/bin/sh
# shellcheck source=../ctx-lib.sh
CTX_BIN=${CTX_BIN:-$(cd "$(dirname "$0")/.." && pwd)}
. "$CTX_BIN/ctx-lib.sh"
# ctx compact [--apply] — journal compaction. Without --apply only lists; the agent writes the summary.
ctx_init
apply=""
[ "${1:-}" = --apply ] && apply=1
keep=$(ctx_cfg_int compact_keep_entries 10)
total=$(ctx_entries | wc -l | tr -d ' ')
old=$(ctx_entries | awk -v n="$total" -v k="$keep" 'NR <= n - k')
drafts=$(for f in $old; do ctx_is_draft "$f" && printf '%s\n' "$f"; done)
old=$(for f in $old; do ctx_is_draft "$f" || printf '%s\n' "$f"; done)
answered=$(awk '/^##[^#]/ { on = index($0, "<!-- ctx:open -->") > 0 } on && /^- Q-/ { q = $0 } on && /✅/ && q != "" { print q; q = "" }' .context/QUESTIONS.md 2>/dev/null)

if [ -z "$apply" ]; then
	ctx_say "Compaction plan: $total entries, keeping the newest $keep."
	if [ -n "$old" ]; then
		ctx_say "Entries to archive (read them first and move lasting knowledge to DECISIONS / GOTCHAS / MAP):"
		printf '%s\n' "$old" | sed 's/^/  /'
		month=$(printf '%s\n' "$old" | head -n 1 | sed 's|.*/\([0-9]\{4\}\)\([0-9]\{2\}\).*|\1-\2|')
		ctx_say "Write the period summary to .context/journal/archive/SUMMARY-$month.md (or the matching month)."
	else
		ctx_say "No entries to archive."
	fi
	[ -n "$drafts" ] && { ctx_say "Old drafts (left in place — finish or ask their authors):"; printf '%s\n' "$drafts" | sed 's/^/  /'; }
	[ -n "$answered" ] && { ctx_say "Answered questions to move to the archive section:"; printf '%s\n' "$answered" | cut -c1-120 | sed 's/^/  /'; }
	ctx_say "Also: mark obsolete gotchas '[resolved $(ctx_today)] reason' and replaced decisions 'superseded by D-…'."
	ctx_say "Then: sh .context/bin/ctx compact --apply, and a journal entry about the compaction."
	exit 0
fi

mkdir -p .context/journal/archive || ctx_die "cannot create .context/journal/archive"
moved=0
for f in $old; do
	dest=".context/journal/archive/$(basename "$f")"
	if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then git mv "$f" "$dest" || continue
	else mv "$f" "$dest" || continue; fi
	moved=$((moved + 1))
done
if [ -n "$answered" ]; then
	tmp=$(ctx_tmp) || ctx_die "cannot create a temp file"
	awk '
		function flushq() { if (q != "") { if (closed) arch = arch q; else printf "%s", q }; q = "" }
		/^##[^#]/ { flushq(); on = index($0, "<!-- ctx:open -->") > 0; print; next }
		on && /^- Q-/ { flushq(); q = $0 "\n"; closed = index($0, "✅") > 0; next }
		on && q != "" && /^[ \t]+/ { q = q $0 "\n"; if (index($0, "✅")) closed = 1; next }
		on && q != "" { flushq() }
		{ print }
		END { flushq(); printf "%s", arch }' .context/QUESTIONS.md > "$tmp" && cat "$tmp" > .context/QUESTIONS.md
	rm -f "$tmp"
fi
ctx_say "Archived $moved entries; answered questions moved to the archive section."
ctx_say "Now write the summary file and a journal entry, then commit."
exit 0
