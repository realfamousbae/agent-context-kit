#!/bin/sh
# shellcheck source=../ctx-lib.sh
CTX_BIN=${CTX_BIN:-$(cd "$(dirname "$0")/.." && pwd)}
. "$CTX_BIN/ctx-lib.sh"
# ctx end — session exit checkpoint.
#   ctx end [--agent A]                         compare with the goal: shows goal, changes, claims, what the entry lacks
#   ctx end --outcome met|partly|not-met [--pause] [--agent A]
#                                               finish the entry with that outcome and release your claims
#                                               (done when met, paused otherwise or with --pause); nothing is committed
ctx_init
agent_arg="" outcome="" pause=""
while [ $# -gt 0 ]; do
	case $1 in
		--agent) agent_arg=${2:-}; shift ;;
		--outcome) outcome=${2:-}; shift ;;
		--pause) pause=1 ;;
		*) ctx_die "unknown argument: $1 (see ctx help)" ;;
	esac
	shift
done
agent=$(ctx_agent "$agent_arg")
[ -n "$agent_arg$CTX_AGENT" ] || agent=""
sd=$(ctx_state_dir) && : > "$sd/ending" 2>/dev/null

if [ -z "$outcome" ]; then
	ctx_checkpoint_card end "${agent:-$(ctx_agent)}"
	ctx_say "Then: ctx end --outcome met|partly|not-met. If the goal is not met, tell the user what is missing and ask how to proceed."
	exit 0
fi
ctx_outcome_valid "$outcome" && [ "$outcome" != in-progress ] || ctx_die "--outcome: met | partly | not-met"
"${CTX_SHELL:-sh}" "$CTX_BIN/cmd/entry.sh" --finish --outcome "$outcome" ${agent:+--agent "$agent"} || exit 1
me=$(ctx_author)
ctx_tasks_in now | while IFS= read -r l; do
	[ "$(ctx_task_field "$l" owner)" = "$me" ] || continue
	case $l in (*" — paused "*) continue ;; esac
	id=$(ctx_task_field "$l" id)
	if [ "$outcome" = met ] && [ -z "$pause" ]; then
		"${CTX_SHELL:-sh}" "$CTX_BIN/cmd/claim.sh" --done "$id" --no-commit >/dev/null && ctx_say "$id → Done"
	else
		"${CTX_SHELL:-sh}" "$CTX_BIN/cmd/claim.sh" --pause "$id" --no-commit >/dev/null && ctx_say "$id paused"
	fi
done
ctx_say "Commit the code and .context/ together (in the user's name, no AI co-author lines); push only if the user agrees."
[ "$outcome" = met ] || ctx_say "Outcome $outcome: tell the user what is missing and what you propose next."
exit 0
