#!/bin/sh
# shellcheck source=../ctx-lib.sh
CTX_BIN=${CTX_BIN:-$(cd "$(dirname "$0")/.." && pwd)}
. "$CTX_BIN/ctx-lib.sh"
# ctx end — end-of-session checklist. Also arms the Claude Code Stop hook: from now on stopping with an
# unfinished entry is blocked (until `ctx entry --finish`).
ctx_init
agent_arg=""
[ "${1:-}" = --agent ] && agent_arg=${2:-}
sd=$(ctx_state_dir) && : > "$sd/ending" 2>/dev/null
me=$(ctx_author)
draft=$(ctx_my_draft "$( [ -n "$agent_arg$CTX_AGENT" ] && ctx_agent "$agent_arg")" 2>/dev/null)

ctx_say "Session end checklist ($me):"
if [ -n "$draft" ]; then
	missing=$(ctx_entry_missing "$draft" | tr '\n' ' ')
	ctx_say "1. Finish the journal draft $draft"
	[ -n "$missing" ] && ctx_say "   still empty (required): $missing"
	ctx_say "   then: sh .context/bin/ctx entry --finish"
else
	last=$(ctx_my_last_done)
	ctx_say "1. No draft. If this session changed anything, create one: sh .context/bin/ctx entry --agent <claude|codex> --model <id>"
	[ -n "$last" ] && ctx_say "   (or update your last entry $last if this continues the same session)"
fi
mine=$(ctx_tasks_in now | while IFS= read -r l; do [ "$(ctx_task_field "$l" owner)" = "$me" ] && printf '%s\n' "$l"; done)
if [ -n "$mine" ]; then
	ctx_say "2. Release your claims: sh .context/bin/ctx claim --done T-…  (or --pause T-…)"
	printf '%s\n' "$mine" | sed 's/^/   /'
else
	ctx_say "2. No claims of yours in Now."
fi
ctx_say "3. GOTCHAS / DECISIONS / MAP updated for anything non-obvious you found?"
ctx_say "4. Commit code and .context/ together, in the user's name, no AI co-author lines."
ctx_say "5. Push only with the user's consent."
exit 0
