#!/bin/sh
# shellcheck source=../ctx-lib.sh
CTX_BIN=${CTX_BIN:-$(cd "$(dirname "$0")/.." && pwd)}
. "$CTX_BIN/ctx-lib.sh"
# ctx start — session entry in one call: journal draft with the goal (and plan), plus a claim when --area is given.
#   ctx start --goal "what and how we know it is done" [--plan "steps"] [T-… | --new "Title"] [--area "paths"]
#             [--agent claude|codex] [--model ID] [--push|--no-push|--no-commit]
# --no-commit: write the claim into TASKS.md without committing it (e.g. the user said "do not commit",
#   or the sandbox cannot write .git); it then travels with your next commit.
ctx_init
goal="" plan="" task="" title="" area="" agent_arg="" model_arg="" push=""
while [ $# -gt 0 ]; do
	case $1 in
		--goal) goal=${2:-}; shift ;;
		--plan) plan=${2:-}; shift ;;
		--new) title=${2:-}; shift ;;
		--area) area=${2:-}; shift ;;
		--agent) agent_arg=${2:-}; shift ;;
		--model) model_arg=${2:-}; shift ;;
		--push|--no-push|--no-commit) push=$1 ;;
		T-*) task=$1 ;;
		*) ctx_die "unknown argument: $1 (see ctx help)" ;;
	esac
	shift
done
[ -n "$goal" ] || ctx_die 'usage: ctx start --goal "what the user wants and how you will know it is done" [--area "paths"]'
agent=$(ctx_agent "$agent_arg")

if [ -n "$area" ] || [ -n "$task" ] || [ -n "$title" ]; then
	# title from the goal: first clause, cut at a word boundary
	[ -n "$task$title" ] || title=$(printf '%s' "$goal" | tr '\n' ' ' | sed 's/[;:.] .*$//' |
		awk '{ if (length($0) <= 70) { print; exit } s = substr($0, 1, 70); sub(/ [^ ]*$/, "", s); print s "…" }')
	set -- --agent "$agent" ${push:+"$push"}
	[ -n "$area" ] && set -- "$@" --area "$area"
	if [ -n "$task" ]; then set -- "$task" "$@"; else set -- --new "$title" "$@"; fi
	"${CTX_SHELL:-sh}" "$CTX_BIN/cmd/claim.sh" "$@" || exit 1
fi

f=$("${CTX_SHELL:-sh}" "$CTX_BIN/cmd/entry.sh" --agent "$agent" ${model_arg:+--model "$model_arg"} 2>/dev/null) ||
	ctx_die "could not create the journal draft"
oneline() { printf '%s' "$1" | tr '\r\n' '  ' | sed 's/  */ /g'; }
if [ -n "$(ctx_section "$f" goal | ctx_content)" ]; then
	ctx_section_append "$f" goal "- (updated) $(oneline "$goal")"
else
	ctx_section_append "$f" goal "- $(oneline "$goal")"
fi
[ -n "$plan" ] && ctx_section_append "$f" plan "- $(oneline "$plan")"
ctx_say "Journal draft: $f (goal recorded)."
ctx_say "Work by your plan. Checkpoints: commit (finished entry, ctx entry --finish), push/deploy (outcome met or the user's OK), end: ctx end."
exit 0
