#!/bin/sh
# shellcheck source=../ctx-lib.sh
CTX_BIN=${CTX_BIN:-$(cd "$(dirname "$0")/.." && pwd)}
. "$CTX_BIN/ctx-lib.sh"
# ctx check — enforcement.
#   --commit-msg FILE  commit-msg hook: strip AI co-author lines, require a finished journal entry
#                      staged with code ([no-ctx] in the message or CTX_SKIP=1 bypasses)
#   --staged           the same journal check without a message
#   --pre-commit       pre-commit hook: secret patterns in .context/, warnings about others' claims
#   --soft [--format claude|codex]  Stop hook of Claude Code or Codex (hook JSON on stdin); exit 2 = message
#                      to the agent; Codex requires JSON on stdout when exiting 0, so codex prints {}
#   --range A..B [--strict]  CI report of code commits without a journal entry
ctx_init

mode="" msg_file="" range="" strict="" format=claude agent_arg=""
while [ $# -gt 0 ]; do
	case $1 in
		--commit-msg) mode=msg; msg_file=${2:-}; shift ;;
		--staged) mode=staged ;;
		--pre-commit) mode=precommit ;;
		--soft) mode=soft ;;
		--range) mode=range; range=${2:-}; shift ;;
		--strict) strict=1 ;;
		--format) format=${2:-claude}; shift ;;
		--agent) agent_arg=${2:-}; shift ;;
		*) ctx_die "unknown option: $1 (see ctx help)" ;;
	esac
	shift
done

in_merge() {
	[ -f "$CTX_GIT_DIR/MERGE_HEAD" ] || [ -f "$CTX_GIT_DIR/CHERRY_PICK_HEAD" ] || [ -f "$CTX_GIT_DIR/REVERT_HEAD" ]
}

staged_code() { git diff --cached --name-only 2>/dev/null | grep -v '^\.context/' | head -n 20; }

# staged_entries STATUS — staged journal entries (added or modified) whose staged status is STATUS (done|draft).
staged_entries() {
	git diff --cached --name-only --diff-filter=AM 2>/dev/null | grep '^\.context/journal/[^/]*\.md$' |
		while IFS= read -r f; do
			st=$(git show ":$f" 2>/dev/null | awk 'NR == 1 && /^---/ { on = 1; next } on && /^---/ { exit } on && /^status:/ { sub(/^status:[ \t]*/, ""); sub(/[ \t\r]*$/, ""); print; exit }')
			[ "$st" = draft ] && s=draft || s="done"
			[ "$s" = "$1" ] && printf '%s\n' "$f"
		done
}

# journal_ok — 0 if the staged commit satisfies the journal rule; prints the reason otherwise.
journal_ok() {
	local code drafts
	in_merge && return 0
	code=$(staged_code)
	[ -n "$code" ] || return 0
	[ -n "$(staged_entries "done")" ] && return 0
	drafts=$(staged_entries draft)
	cat <<MSG
ctx: commit rejected — code changes need a finished journal entry in the same commit.
  Code in this commit (first files):
$(printf '%s\n' "$code" | sed 's/^/    /')
MSG
	if [ -n "$drafts" ]; then
		printf '  Staged entry is still a draft: %s\n' "$drafts"
		printf '  Fix: fill it in, run `sh .context/bin/ctx entry --finish`, then `git add %s` and commit again.\n' "$drafts"
	else
		d=$(ctx_my_draft 2>/dev/null)
		if [ -n "$d" ]; then
			printf '  Your draft: %s\n  Fix: fill it in, `sh .context/bin/ctx entry --finish`, `git add %s`, commit again.\n' "$d" "$d"
		else
			printf '  Fix: `sh .context/bin/ctx entry --agent <claude|codex|human> --model <id>`, fill it in,\n'
			printf '       `sh .context/bin/ctx entry --finish`, `git add .context/journal/<file>`, commit again.\n'
			printf '  A later commit of the same session may update the same entry instead.\n'
		fi
	fi
	printf '  Trivial change (typo, formatting)? Put [no-ctx] in the commit message.\n'
	return 1
}

strip_ai() {
	local tmp
	[ "$(ctx_cfg strip_ai_coauthor true)" = true ] || return 0
	tmp=$(ctx_tmp) || return 0
	awk '
		{ l = tolower($0) }
		l ~ /^co-authored-by:/ && l ~ /(claude|anthropic|codex|openai|chatgpt|gpt-|copilot|gemini|cursor|devin|aider)/ { next }
		l ~ /generated (with|by) .*(claude|codex|chatgpt|copilot|gemini|cursor|ai)/ { next }
		{ print }' "$1" > "$tmp" && cat "$tmp" > "$1"
	rm -f "$tmp"
}

case $mode in
msg)
	[ -f "$msg_file" ] || ctx_die "--commit-msg needs the message file"
	strip_ai "$msg_file"
	grep -v '^#' "$msg_file" | grep -F -q '[no-ctx]' && exit 0
	if reason=$(journal_ok); then exit 0; fi
	if [ "${CTX_SKIP:-}" = 1 ]; then
		printf '\nCtx-Skip: CTX_SKIP\n' >> "$msg_file"
		ctx_err "CTX_SKIP=1: committing code without a journal entry (counted by ctx status)."
		exit 0
	fi
	printf '%s\n' "$reason" >&2
	exit 1 ;;
staged)
	[ "${CTX_SKIP:-}" = 1 ] && exit 0
	reason=$(journal_ok) && exit 0
	printf '%s\n' "$reason" >&2
	exit 1 ;;
precommit)
	rc=0
	hits=$(git diff --cached -U0 --no-color --no-ext-diff -- .context \
		':(exclude).context/bin' ':(exclude).context/templates' ':(exclude).context/PROTOCOL.md' 2>/dev/null |
		awk '
			/^\+\+\+ / { f = substr($0, 7); next }
			/^\+/ { print f ": " substr($0, 2) }' |
		grep -E -i -e 'sk-[A-Za-z0-9_-]{16,}' -e 'ghp_[A-Za-z0-9]{20,}' -e 'github_pat_[A-Za-z0-9_]{20,}' \
			-e 'xox[bp]-[A-Za-z0-9-]{10,}' -e 'AKIA[0-9A-Z]{16}' -e 'BEGIN [A-Z ]*PRIVATE KEY' \
			-e 'password[[:space:]]*[=:][[:space:]]*[^[:space:]]' -e 'token[[:space:]]*=[[:space:]]*[^[:space:]]' \
			-e '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}' | head -n 10)
	if [ -n "$hits" ] && [ "${CTX_SKIP_SECRETS:-}" != 1 ]; then
		ctx_err "commit rejected — possible secret or personal data in .context/:"
		printf '%s\n' "$hits" | cut -c1-160 | sed 's/^/    /' >&2
		ctx_err "Remove it (.context/ is shared and permanent). False positive: CTX_SKIP_SECRETS=1 git commit …"
		rc=1
	fi
	# Warn (never block) when staged files fall into someone else's live claim.
	me=$(ctx_author)
	files=$(git diff --cached --name-only 2>/dev/null | grep -v '^\.context/')
	if [ -n "$files" ]; then
		{ ctx_tasks_in now; ctx_remote_claims | cut -f2-; } | while IFS= read -r l; do
			o=$(ctx_task_field "$l" owner)
			[ -n "$o" ] && [ "$o" != "$me" ] || continue
			case $l in (*" — paused "*) continue ;; esac
			a=$(ctx_task_field "$l" area)
			for f in $files; do
				set -f
				for i in $a; do
					if ctx_path_in_area "$f" "$i"; then
						ctx_err "warning: $f is in $(ctx_task_field "$l" id) claimed by @$o — did you agree? (ctx ask @$o)"
						break
					fi
				done
				set +f
			done
		done
	fi
	exit $rc ;;
soft)
	ctx_hook_read
	if [ "$format" = codex ]; then trap 'rc=$?; [ $rc -eq 0 ] && echo "{}"; exit $rc' EXIT; fi
	# Without hook input we cannot see stop_hook_active: never block then (no loops).
	[ -n "$CTX_HOOK_JSON" ] || exit 0
	[ "$(ctx_hook_field stop_hook_active)" = true ] && exit 0
	if [ -n "$(ctx_hook_field cwd)" ]; then
		ctx_hook_cd
		r=$(git rev-parse --show-toplevel 2>/dev/null) && [ -d "$r/.context" ] && cd "$r" || exit 0
		CTX_GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
		case $CTX_GIT_DIR in /*|?:*) ;; *) CTX_GIT_DIR="$r/$CTX_GIT_DIR" ;; esac
	fi
	sid=$(ctx_hook_field session_id | tr -c 'A-Za-z0-9_-' '_')
	[ -n "$sid" ] || sid=nosession
	sd=$(ctx_state_dir)
	agent=$(ctx_agent "$agent_arg")
	draft=$(ctx_my_draft "$agent" 2>/dev/null)
	if [ -n "$sd" ] && [ -f "$sd/ending" ]; then
		if [ -z "$draft" ]; then
			last=$(ctx_my_last_done)
			[ -n "$last" ] && exit 0
			ctx_err "ctx end was declared but there is no journal entry. Create it: sh .context/bin/ctx entry --agent $agent --model <id>"
			exit 2
		fi
		missing=$(ctx_entry_missing "$draft")
		if [ -n "$missing" ]; then
			ctx_err "ctx end was declared but $draft is missing: $(echo "$missing" | tr '\n' ' ')— fill them in and run: sh .context/bin/ctx entry --finish"
			exit 2
		fi
		exit 0
	fi
	changed=$(git status --porcelain 2>/dev/null | cut -c4- | grep -v '^\.context/' | grep -v '^"\.context/' | head -n 1)
	[ -n "$changed" ] || exit 0
	if [ -n "$draft" ] && ctx_entry_has_content "$draft"; then exit 0; fi
	# a finished entry of mine that is not committed yet belongs to this session
	git status --porcelain -- .context/journal 2>/dev/null | grep -v -e '^D' -e '^.D' | cut -c4- | while IFS= read -r f; do
		[ "$(ctx_entry_author "$f")" = "$(ctx_author)" ] && echo y
	done | grep -q y && exit 0
	if [ -n "$sd" ]; then
		[ -f "$sd/reminded-$sid" ] && exit 0
		: > "$sd/reminded-$sid" 2>/dev/null || exit 0
	else
		exit 0  # cannot remember the reminder: stay silent rather than nag every turn
	fi
	if [ -n "$draft" ]; then
		ctx_err "ctx reminder (once per session): you changed code but your journal draft $draft is empty. Write what you learned into it now; it must be finished (ctx entry --finish) before committing."
	else
		ctx_err "ctx reminder (once per session): you changed code but have no journal draft. Run: sh .context/bin/ctx entry --agent $agent --model <your model id> — and record findings as you go."
	fi
	exit 2 ;;
range)
	[ -n "$range" ] || ctx_die "usage: ctx check --range A..B"
	report=$(ctx_commit_classes "$range")
	missing=$(printf '%s\n' "$report" | awk -F '\t' '$2 == "missing"')
	total=$(printf '%s\n' "$report" | awk -F '\t' 'NF && $2 != "context"' | wc -l | tr -d ' ')
	n=$(printf '%s\n' "$missing" | awk 'NF' | wc -l | tr -d ' ')
	ctx_say "ctx check $range: $total code commit(s), $n without a journal entry."
	[ "$n" -gt 0 ] && printf '%s\n' "$missing" | awk -F '\t' '{ printf "  %s %s %s — %s [%s]\n", $1, $4, $3, $5, $6 }'
	printf '%s\n' "$report" | awk -F '\t' '$2 == "noctx" || $2 == "skip" { n++ } END { if (n) printf "  (%d bypass(es) via [no-ctx] or CTX_SKIP)\n", n }'
	[ -n "$strict" ] && [ "$n" -gt 0 ] && exit 1
	exit 0 ;;
*) ctx_die "usage: ctx check --commit-msg FILE | --staged | --pre-commit | --soft | --range A..B" ;;
esac
