#!/bin/sh
# ctx checkpoint — compare the work with the session goal before an important step.
#   ctx checkpoint [push|deploy|commit|end] [--agent A]    print the checkpoint card
#   ctx checkpoint --hook [--format claude|codex] [--agent A]
#       PreToolUse hook. Silent (no output, no tokens) unless the command is a push/deploy/publish-like step
#       (kit.json checkpoint_patterns adds more). Then, if the session's entry is not finished with outcome "met",
#       Claude Code gets "ask" (the user confirms in the permission prompt) and Codex gets "deny" with the card
#       as the reason (Codex has no "ask" yet). Prefixing the command with CTX_CONFIRMED=1 skips the gate —
#       only after the user agreed. Never answers "allow": the user's own permission rules stay in charge.
CTX_BIN=${CTX_BIN:-$(cd "$(dirname "$0")/.." && pwd)}

hook="" format=claude agent_arg="" kind=""
while [ $# -gt 0 ]; do
	case $1 in
		--hook) hook=1 ;;
		--format) format=${2:-claude}; shift ;;
		--agent) agent_arg=${2:-}; shift ;;
		push|deploy|commit|end) kind=$1 ;;
	esac
	shift
done

if [ -n "$hook" ]; then
	# Fast path: plain sh, no git, no ctx-lib — this runs before every Bash call in Codex.
	input=""
	[ -t 0 ] || input=$(cat 2>/dev/null)
	cmd=$(printf '%s' "$input" | tr -d '\r\n' | awk '
		{
			i = index($0, "\"command\""); if (!i) exit
			s = substr($0, i + 9); sub(/^[ \t]*:[ \t]*"/, "", s); out = ""
			for (j = 1; j <= length(s); j++) {
				c = substr(s, j, 1)
				if (c == "\\") { j++; out = out substr(s, j, 1); continue }
				if (c == "\"") break
				out = out c
			}
			print out
		}')
	case $cmd in *CTX_CONFIRMED=1*) exit 0 ;; esac
	extra=$(sed -n 's/.*"checkpoint_patterns"[ ]*:[ ]*"\([^"]*\)".*/\1/p' "$CTX_BIN/../kit.json" 2>/dev/null)
	kind=""
	for p in "git push" deploy publish "terraform apply" "kubectl apply" "helm upgrade" "helm install" \
		"docker push" "railway up" "release create" $(printf '%s' "$extra" | tr '|' '\n' | sed 's/ /_/g'); do
		p=$(printf '%s' "$p" | sed 's/_/ /g')
		case $cmd in *"$p"*) kind=$p; break ;; esac
	done
	[ -n "$kind" ] || exit 0
	first=$(printf '%s' "$cmd" | sed 's/^\([A-Za-z_][A-Za-z0-9_]*=[^ ]* \)*//' | awk '{ print $1 }')
	case $first in cat|less|more|head|tail|grep|rg|ls|find|echo|printf|sed|awk|wc|vi|vim|nano|code|open|man) exit 0 ;; esac
	if [ "$first" = git ]; then
		case $cmd in *"git push"*) ;; *) exit 0 ;; esac
	fi
fi

# shellcheck source=../ctx-lib.sh
. "$CTX_BIN/ctx-lib.sh"
if [ -n "$hook" ]; then
	# shellcheck disable=SC2034  # read by ctx_hook_cd
	CTX_HOOK_JSON=$(printf '%s' "$input" | tr -d '\r\n')
	ctx_hook_cd
	r=$(git rev-parse --show-toplevel 2>/dev/null) && [ -d "$r/.context" ] || exit 0
fi
ctx_init
agent=$(ctx_agent "$agent_arg")

if [ -z "$hook" ]; then
	ctx_checkpoint_card "${kind:-push}" "$agent"
	exit 0
fi

e=$(ctx_my_current_entry "$agent" 2>/dev/null)
if [ -n "$e" ] && [ "$(ctx_frontmatter "$e" outcome)" = met ] && [ "$(ctx_frontmatter "$e" status)" = "done" ] &&
	[ -z "$(ctx_entry_missing "$e")" ]; then
	exit 0
fi
card=$(ctx_checkpoint_card "$kind" "$agent")
if [ "$format" = codex ]; then
	reason="$card
Stopped before \"$kind\": the session outcome is not \"met\". Tell the user where things stand and ask whether to proceed. If they agree, rerun the same command prefixed with CTX_CONFIRMED=1; or finish first with ctx end --outcome met."
	printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$(printf '%s\n' "$reason" | ctx_json_string)"
else
	reason="$card
The session outcome is not \"met\" yet — confirm \"$kind\" only if this is what you want."
	printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$(printf '%s\n' "$reason" | ctx_json_string)"
fi
exit 0
