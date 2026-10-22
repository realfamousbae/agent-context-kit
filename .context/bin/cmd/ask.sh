#!/bin/sh
# shellcheck source=../ctx-lib.sh
CTX_BIN=${CTX_BIN:-$(cd "$(dirname "$0")/.." && pwd)}
. "$CTX_BIN/ctx-lib.sh"
# ctx ask — questions between participants and agents (.context/QUESTIONS.md).
#   ctx ask @who "question" [--task T-…] [--agent A] [--commit] [--push|--no-push]
#   ctx ask --answer Q-… "answer" [--keep-open] [--agent A] [--commit] [--push|--no-push]
#   ctx ask --list [--all]
ctx_init
Q=.context/QUESTIONS.md
[ -f "$Q" ] || ctx_die "missing $Q — run install.sh"

mode=ask who="" text="" task="" agent_arg="" keep_open="" commit="" push_flag="" answer_id=""
while [ $# -gt 0 ]; do
	case $1 in
		--answer) mode=answer; answer_id=${2:-}; shift ;;
		--list) mode=list ;;
		--all) mode=listall ;;
		--task) task=${2:-}; shift ;;
		--agent) agent_arg=${2:-}; shift ;;
		--keep-open) keep_open=1 ;;
		--commit) commit=1 ;;
		--push) commit=1; push_flag=auto ;;
		--no-push) push_flag=never ;;
		@*) who=$1 ;;
		-*) ctx_die "unknown option: $1 (see ctx help)" ;;
		*) text=$1 ;;
	esac
	shift
done
me="$(ctx_author)/$(ctx_agent "$agent_arg")"
oneline() { printf '%s' "$1" | tr '\r\n' '  ' | sed 's/  */ /g'; }

save() {
	[ -n "$commit" ] || { ctx_say "Not committed: it goes with your next commit (or use --commit)."; return 0; }
	if ctx_commit_paths "$1" "$Q"; then
		ctx_say "Committed: $1"
		ctx_maybe_push "$(ctx_push_mode "$push_flag")" "question"
	else
		ctx_say "WARNING: could not commit (read-only .git or sandbox?). Ask the user to run:"
		ctx_say "  git add $Q && git commit -m \"$1\" -- $Q"
	fi
}

case $mode in
	list|listall)
		if [ "$mode" = listall ]; then
			ctx_questions "$Q" all ""
		else
			mine=$(ctx_questions "$Q" mine "$(ctx_my_addressees "$agent_arg")")
			others=$(ctx_questions "$Q" others "$(ctx_my_addressees "$agent_arg")")
			[ -n "$mine" ] && { ctx_say "Open, addressed to you:"; ctx_say "$mine"; }
			[ -n "$others" ] && { ctx_say "Open, for others:"; ctx_say "$others"; }
			[ -n "$mine$others" ] || ctx_say "No open questions."
		fi
		exit 0 ;;
	ask)
		[ -n "$who" ] && [ -n "$text" ] || ctx_die 'usage: ctx ask @who "question" [--task T-…]'
		case $who in @*/*|@) ctx_die "addressee is @<author>, @claude, @codex or @all" ;; esac
		id=$(ctx_next_id Q)
		line="- $id · $who · from $me · $(oneline "$text")"
		[ -n "$task" ] && line="$line ($task)"
		tmp=$(ctx_tmp) || ctx_die "cannot create a temp file"
		awk -v l="$line" '
			index($0, "<!-- ctx:archive -->") && !done {
				# drop trailing blank lines of the Open section, insert, keep one blank line
				while (nb > 0 && buf[nb] ~ /^[ \t\r]*$/) nb--
				for (i = 1; i <= nb; i++) print buf[i]
				print l; print ""; print; done = 1; nb = 0; next
			}
			!done { buf[++nb] = $0; next }
			{ print }
			END { if (!done) { for (i = 1; i <= nb; i++) print buf[i]; print l } }' "$Q" > "$tmp" && cat "$tmp" > "$Q"
		rm -f "$tmp"
		ctx_say "$id → $who"
		save "ctx: ask $id" ;;
	answer)
		[ -n "$answer_id" ] && [ -n "$text" ] || ctx_die 'usage: ctx ask --answer Q-… "answer"'
		grep -q -- "^- $answer_id " "$Q" || ctx_die "no question $answer_id in $Q"
		mark=" ✅"; [ -n "$keep_open" ] && mark=""
		line="  - answer $(ctx_today) · $me: $(oneline "$text")$mark"
		tmp=$(ctx_tmp) || ctx_die "cannot create a temp file"
		awk -v id="- $answer_id " -v l="$line" '
			index($0, id) == 1 { on = 1; print; next }
			on && /^[ \t]+/ { print; next }
			on { print l; on = 0; done = 1 }
			{ print }
			END { if (on) print l }' "$Q" > "$tmp" && cat "$tmp" > "$Q"
		rm -f "$tmp"
		ctx_say "Answered $answer_id${mark:+ (closed)}"
		save "ctx: answer $answer_id" ;;
esac
exit 0
