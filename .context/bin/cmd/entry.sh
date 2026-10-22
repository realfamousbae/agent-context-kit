#!/bin/sh
# shellcheck source=../ctx-lib.sh
CTX_BIN=${CTX_BIN:-$(cd "$(dirname "$0")/.." && pwd)}
. "$CTX_BIN/ctx-lib.sh"
# ctx entry — the session's journal entry.
#   ctx entry [--agent A] [--model M] [--new]   create a draft, or print the existing one
#   ctx entry --finish [--agent A]              check required sections, drop empty ones, set status: done
#   ctx entry --path [--agent A]                print the current draft path (exit 1 if none)
ctx_init

mode=create agent_arg="" model_arg="" force_new=""
while [ $# -gt 0 ]; do
	case $1 in
		--agent) agent_arg=${2:-}; shift ;;
		--model) model_arg=${2:-}; shift ;;
		--new) force_new=1 ;;
		--finish|--done) mode=finish ;;
		--path) mode=path ;;
		*) ctx_die "unknown option: $1 (see ctx help)" ;;
	esac
	shift
done
agent=$(ctx_agent "$agent_arg")
[ -n "$agent_arg" ] || [ -n "${CTX_AGENT:-}" ] || agent=""

finish() {
	local f missing empty k tmp lines
	f=$(ctx_my_draft "$agent") || ctx_die "no draft entry of $(ctx_author) — create one with: ctx entry --agent <claude|codex> --model <id>"
	missing=$(ctx_entry_missing "$f")
	if [ -n "$missing" ]; then
		ctx_err "$f: fill in the required sections first: $(echo "$missing" | tr '\n' ' ')"
		ctx_err "(anchors <!-- ctx:done -->, <!-- ctx:verified -->, <!-- ctx:next -->; write 'not verified' if so)"
		exit 1
	fi
	empty=""
	for k in learned decisions risks for-others for-humans files; do
		[ -n "$(ctx_section "$f" "$k" | ctx_content)" ] || empty="$empty $k "
	done
	tmp=$(ctx_tmp) || ctx_die "cannot create a temp file"
	awk -v empty="$empty" '
		NR == 1 && /^---/ { fm = 1; print; next }
		fm && /^---/ { fm = 0; print; next }
		fm { if ($0 ~ /^status:/) print "status: done"; else print; next }
		/^##[^#]/ {
			skip = 0
			if (match($0, /<!-- ctx:[a-z-]+ -->/)) {
				k = substr($0, RSTART + 9, RLENGTH - 13)
				if (index(empty, " " k " ")) { skip = 1; next }
			}
			if (blank_pending && printed) print ""
			blank_pending = 0; print; printed = 1; next
		}
		skip { next }
		/^[ \t]*<!--.*-->[ \t\r]*$/ { next }
		/^[ \t\r]*$/ { blank_pending = 1; next }
		{ if (blank_pending && printed) print ""; blank_pending = 0; print; printed = 1 }
	' "$f" > "$tmp" && cat "$tmp" > "$f"
	rm -f "$tmp"
	sd=$(ctx_state_dir) && rm -f "$sd/ending"
	lines=$(awk '/^---/ { fm++; next } fm >= 2' "$f" | ctx_content | wc -l | tr -d ' ')
	ctx_say "$f: status done ($lines lines)."
	[ "$lines" -le 40 ] || ctx_say "WARNING: longer than ~40 lines. Keep only what is not in the code or the commit message."
	ctx_say "Stage it with the code: git add $f"
}

case $mode in
	path) ctx_my_draft "$agent" || exit 1; exit 0 ;;
	finish) finish; exit 0 ;;
esac

[ -n "$agent" ] || agent=$(ctx_agent)
if [ -z "$force_new" ] && f=$(ctx_my_draft "$agent"); then
	ctx_say "$f"
	ctx_say "(existing draft — keep filling it in; ctx entry --finish when done)" >&2
	exit 0
fi

author=$(ctx_author)
mkdir -p "$CTX_JOURNAL" || ctx_die "cannot create $CTX_JOURNAL"
f=".context/journal/$(ctx_stamp_utc)-$author-$agent.md"
[ -e "$f" ] && f=".context/journal/$(date -u +%Y%m%d-%H%M%SZ)-$author-$agent.md"
tpl="$(ctx_template_dir)/templates/entry.md"
[ -f "$tpl" ] || ctx_die "missing template $tpl — run install.sh --update"

tasks=$(ctx_tasks_in now | while IFS= read -r l; do
	[ "$(ctx_task_field "$l" owner)" = "$author" ] && ctx_task_field "$l" id
done | awk 'NF { printf "%s%s", (n++ ? ", " : ""), $0 }')

esc() { printf '%s' "$1" | sed 's/[|&\\]/\\&/g'; }
sed -e "s|{{date}}|$(esc "$(ctx_now_local)")|" \
	-e "s|{{author}}|$(esc "$author")|" \
	-e "s|{{agent}}|$(esc "$agent")|" \
	-e "s|{{model}}|$(esc "$(ctx_model "$model_arg")")|" \
	-e "s|{{tasks}}|$(esc "$tasks")|" "$tpl" > "$f" || ctx_die "cannot write $f"
ctx_say "$f"
ctx_say "(new draft — fill it in as you go; ctx entry --finish before committing)" >&2
