#!/bin/sh
# ctx brief [--short] [--budget BYTES] [--no-fetch] [--agent A] [--hook [--format claude|codex]]
# Start-of-session summary within a byte budget, highest priority first:
#   warnings, questions to me, tasks in progress, gotchas, others' entries since my last one (all branches),
#   code commits without a journal entry, recent entries, decisions index, map.
# --short (after context compaction): warnings, questions, tasks, gotchas and my current draft.
# --hook: called by an agent's SessionStart hook. Reads the hook JSON on stdin (cwd, source), uses
#   hook_budget_bytes (Claude Code caps hook context at 10,000 characters), and with --format codex
#   prints {"hookSpecificOutput": {"additionalContext": …}} as Codex expects.
# It never fails: any error ends the output early, the exit code is always 0.
# Sections live in variables S0…S9 (alternatives A5, A7), read back through eval.
# shellcheck source=../ctx-lib.sh disable=SC2034
CTX_BIN=${CTX_BIN:-$(cd "$(dirname "$0")/.." && pwd)}
. "$CTX_BIN/ctx-lib.sh"
GIT_OPTIONAL_LOCKS=0
export GIT_OPTIONAL_LOCKS

short="" budget="" fetch=1 agent_arg="" hook="" format=claude
while [ $# -gt 0 ]; do
	case $1 in
		--short) short=1 ;;
		--budget) budget=${2:-}; shift ;;
		--no-fetch) fetch="" ;;
		--agent) agent_arg=${2:-}; shift ;;
		--hook) hook=1 ;;
		--format) format=${2:-claude}; shift ;;
	esac
	shift
done
[ "${CTX_NO_FETCH:-}" = 1 ] && fetch=""
if [ -n "$hook" ]; then
	ctx_hook_read
	ctx_hook_cd
	[ "$(ctx_hook_field source)" = compact ] && short=1
fi

# render_entry NAME LABEL KEYONLY < entry — compact rendering of one journal entry.
render_entry() {
	awk -v name="$1" -v label="$2" -v keyonly="$3" '
		NR == 1 && /^---/ { fm = 1; next }
		fm && /^---/ {
			fm = 0
			printf "### %s — %s/%s, %s, %s%s\n", name, f["author"], f["agent"], f["model"], f["date"], label
			if (f["tasks"] != "" && f["tasks"] != "[]") printf "tasks: %s\n", f["tasks"]
			if (f["status"] == "draft") print "(draft)"
			next
		}
		fm { i = index($0, ":"); if (i) { k = substr($0, 1, i - 1); v = substr($0, i + 1); sub(/^[ \t]+/, "", v); sub(/[ \t\r]+$/, "", v); f[k] = v }; next }
		/^##[^#]/ {
			key = ""
			if (match($0, /<!-- ctx:[a-z-]+ -->/)) key = substr($0, RSTART + 9, RLENGTH - 13)
			head = $0; sub(/[ \t]*<!--.*$/, "", head); sub(/^#+[ \t]*/, "", head)
			inc = !keyonly || key == "done" || key == "next" || key == "for-others" || key == "for-humans"
			pending = 1; next
		}
		/^[ \t\r]*$/ || /^[ \t]*<!--.*-->[ \t\r]*$/ { next }
		inc { if (pending) { print "**" head "**"; pending = 0 } print }
		END { print "" }'
}

brief_main() {
	CTX_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "ctx brief: not inside a git repository — no shared context."; return 0; }
	[ -d "$CTX_ROOT/.context" ] || { echo "ctx brief: no .context/ here — agent-context-kit is not installed."; return 0; }
	ctx_init
	# No temp files: agent sandboxes (Codex read-only) may not allow writing anywhere.
	S0="" S1="" S2="" S3="" S4="" S5="" S6="" S7="" S8="" S9="" A5="" A7=""

	me=$(ctx_author)
	agent=$(ctx_agent "$agent_arg")
	[ -n "$agent_arg$CTX_AGENT" ] || agent="(agent unknown)"
	lang=$(ctx_lang)
	branch=$(git symbolic-ref --short -q HEAD 2>/dev/null || echo "detached HEAD")
	if [ -n "$short" ]; then budget=${budget:-$(ctx_cfg_int brief_short_budget_bytes 8000)}
	elif [ -n "$hook" ] && [ "$format" = claude ]; then budget=${budget:-$(ctx_cfg_int hook_budget_bytes 9500)}
	else budget=${budget:-$(ctx_cfg_int brief_budget_bytes 24000)}; fi
	case $budget in ''|*[!0-9]*) budget=24000 ;; esac

	S0=$(printf '# ctx brief — %s, branch %s, you are %s/%s\nWrite everything in .context/ in language "%s". Rules: .context/PROTOCOL.md.' \
		"$(basename "$CTX_ROOT")" "$branch" "$me" "$agent" "$lang")

	# 1. Warnings
	S1=$({
		[ "$(git config core.hooksPath 2>/dev/null)" = .githooks ] ||
			echo "- Git hooks are off here: run the kit installer, or \`git config core.hooksPath .githooks\`."
		git config ctx.author >/dev/null 2>&1 || echo "- \`git config ctx.author\` is not set; using \"$me\". Set it (and ctx.initials) once per clone."
		[ -n "$(ctx_cfg kit_version "")" ] || echo "- .context/kit.json is missing or unreadable — defaults in use."
		if ctx_has_remote; then
			if [ -n "$fetch" ]; then
				ctx_git_net fetch --quiet --prune origin >/dev/null 2>&1 ||
					echo "- Could not fetch origin (offline or sandbox): other branches and claims may be stale."
			fi
			if counts=$(git rev-list --left-right --count 'HEAD...@{upstream}' 2>/dev/null); then
				ahead=$(echo "$counts" | awk '{ print $1 }'); behind=$(echo "$counts" | awk '{ print $2 }')
				[ "${behind:-0}" -gt 0 ] && echo "- Branch is $behind commit(s) behind upstream: \`git pull --rebase\` before you start."
				if [ "${ahead:-0}" -gt 0 ] && git log --format=%s '@{upstream}..HEAD' 2>/dev/null | grep -q '^ctx: claim '; then
					echo "- Your claim commit is not pushed: others cannot see it."
				fi
			fi
		fi
		n=$(ctx_entries | wc -l | tr -d ' ')
		[ "$n" -gt "$(ctx_cfg_int compact_threshold_entries 30)" ] && echo "- $n journal entries: time to compact (\"ctx compact\")."
		d=$(ctx_my_draft 2>/dev/null) && [ -z "$short" ] && echo "- You have an unfinished draft: $d (continue it; ctx entry returns it)."
		if [ "$(ctx_cfg check_updates false)" = true ]; then
			sd=$(ctx_state_dir); stamp=$(ctx_today_compact); latest=""
			if [ -n "$sd" ] && [ -f "$sd/update-$stamp" ]; then latest=$(cat "$sd/update-$stamp")
			else
				latest=$(ctx_git_net ls-remote --tags --refs "$(ctx_cfg kit_repo "")" 2>/dev/null |
					sed -n 's|.*refs/tags/v\{0,1\}\([0-9][0-9.]*\)$|\1|p' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)
				[ -n "$sd" ] && printf '%s\n' "$latest" > "$sd/update-$stamp" 2>/dev/null
			fi
			cur=$(ctx_cfg kit_version 0)
			if [ -n "$latest" ] && [ "$latest" != "$cur" ] &&
				[ "$(printf '%s\n%s\n' "$cur" "$latest" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)" = "$latest" ]; then
				echo "- agent-context-kit $latest is available (installed $cur): install.sh --update."
			fi
		fi
	})

	# 2. Questions addressed to me
	q=$(ctx_questions .context/QUESTIONS.md mine "$(ctx_my_addressees "$agent_arg")")
	nother=$(ctx_questions .context/QUESTIONS.md others "$(ctx_my_addressees "$agent_arg")" | grep -c '^- Q-')
	S2=$({
		if [ -n "$q" ]; then echo "## Open questions for you — answer: ctx ask --answer Q-… \"…\""; printf '%s\n' "$q"; fi
		[ "${nother:-0}" -gt 0 ] && echo "($nother other open question(s): ctx ask --list)"
	})

	# 3. Tasks in progress and blocked
	S3=$({
		now=$(ctx_tasks_in now)
		remote=$(ctx_remote_claims)
		blocked=$(ctx_tasks_in blocked)
		if [ -n "$now$remote$blocked" ]; then
			echo "## Tasks in progress — claim yours before editing: ctx claim T-… --area \"…\""
			[ -n "$now" ] && printf '%s\n' "$now" | while IFS= read -r l; do
				o=$(ctx_task_field "$l" owner); tag=""
				case $l in (*" — paused "*) tag=" [paused]" ;; (*)
					if [ -n "$o" ]; then
						age=$(ctx_claim_age_days "$l")
						tag=" [${age}d]"; ctx_claim_is_stale "$l" && tag=" [STALE ${age}d — ask @$o before taking over]"
					fi ;;
				esac
				[ "$o" = "$me" ] && tag="$tag (yours)"
				printf '%s%s\n' "$l" "$tag"
			done
			[ -n "$remote" ] && printf '%s\n' "$remote" | awk -F '\t' '{ print $2 " [on " $1 "]" }'
			[ -n "$blocked" ] && { echo "Blocked:"; printf '%s\n' "$blocked"; }
		fi
	})

	# 4. Active gotchas
	g=$(awk '/^- G-/ && !/\[resolved/' .context/GOTCHAS.md 2>/dev/null)
	[ -n "$g" ] && S4=$(echo "## Gotchas (active)"; printf '%s\n' "$g")

	if [ -n "$short" ]; then
		d=$(ctx_my_draft "$( [ -n "$agent_arg$CTX_AGENT" ] && ctx_agent "$agent_arg")" 2>/dev/null)
		if [ -n "$d" ]; then
			S5=$(echo "## Your journal draft: $d (keep filling it in)"; render_entry "$(basename "$d")" "" "" < "$d")
		else
			S5="## No journal draft of yours — start one: ctx entry --agent <claude|codex> --model <id>"
		fi
		order="1 2 3 4 5"
	else
		last=$(ctx_my_last_done); lastname=""
		[ -n "$last" ] && lastname=$(basename "$last")
		# 5. Others' entries after my last one, incl. other branches
		shown=$(for f in $(ctx_entries | awk -v last=".context/journal/$lastname" -v any="${lastname:-1}" 'any == 1 || $0 > last'); do
			[ "$(ctx_entry_author "$f")" = "$me" ] && continue
			ctx_is_draft "$f" && continue
			basename "$f"
		done | tail -n 10)
		refs=$(ctx_remote_branches)
		for b in main master; do
			[ "$b" != "$branch" ] && git rev-parse -q --verify "refs/heads/$b" >/dev/null 2>&1 && refs="$refs $b"
		done
		# ref TAB path of entries that exist only on other branches, first ref wins
		others=$(for r in $refs; do
			git ls-tree --name-only "$r" .context/journal/ 2>/dev/null | grep '\.md$' | while IFS= read -r p; do
				n=$(basename "$p")
				[ -f ".context/journal/$n" ] || [ -f ".context/journal/archive/$n" ] || printf '%s\t%s\n' "$r" "$p"
			done
		done | awk -F '\t' '{ n = $2; sub(/.*\//, "", n); if (!(n in s)) { s[n] = 1; print } }')
		section5() { # KEYONLY
			for n in $shown; do render_entry "$n" "" "$1" < ".context/journal/$n"; done
			printf '%s\n' "$others" | while IFS='	' read -r r p; do
				[ -n "$p" ] && git show "$r:$p" 2>/dev/null | render_entry "$(basename "$p")" " [branch $r]" "$1"
			done
		}
		F5=$(section5 "")
		if [ -n "$(printf '%s' "$F5" | tr -d ' \n')" ]; then
			hdr="## New from others since your last entry${lastname:+ ($lastname)}"
			S5=$(printf '%s\n%s' "$hdr" "$F5")
			A5=$(printf '%s (key sections only)\n' "$hdr"; section5 1)
		fi
		shown="$shown $(printf '%s\n' "$others" | awk -F '\t' 'NF { n = $2; sub(/.*\//, "", n); print n }')"

		# 6. Code commits without a journal entry since my last entry
		range="-n 30 $(ctx_since_install)"
		if [ -n "$last" ]; then
			c=$(git log -1 --format=%H -- "$last" 2>/dev/null)
			[ -n "$c" ] && range="$c..HEAD"
		fi
		# shellcheck disable=SC2086
		miss=$(ctx_commit_classes $range | awk -F '\t' '$2 == "missing"' | head -n 15)
		[ -n "$miss" ] && S6=$(
			echo "## Commits with code but no journal entry (ask their authors or check the diff)"
			printf '%s\n' "$miss" | awk -F '\t' '{ printf "- %s %s %s — %s [%s]\n", $1, $4, $3, $5, $6 }')

		# 7. Recent entries not shown above
		recent=$(ctx_entries | while IFS= read -r f; do ctx_is_draft "$f" || basename "$f"; done |
			tail -n "$(ctx_cfg_int recent_entries 5)" | while IFS= read -r n; do
				case " $(echo $shown) " in (*" $n "*) continue ;; esac
				echo "$n"
			done)
		if [ -n "$recent" ]; then
			S7=$(echo "## Recent journal entries"; for n in $recent; do render_entry "$n" "" "" < ".context/journal/$n"; done)
			A7=$(echo "## Recent journal entries (key sections only)"; for n in $recent; do render_entry "$n" "" 1 < ".context/journal/$n"; done)
		fi

		# 8. Decisions index (active only)
		dec=$(awk '
			/^### D-/ { if (h != "" && !sup) print h; h = $0; sub(/^### /, "- ", h); sup = 0; next }
			/^#/ { if (h != "" && !sup) print h; h = ""; next }
			h != "" && /superseded/ { sup = 1 }
			END { if (h != "" && !sup) print h }' .context/DECISIONS.md 2>/dev/null)
		[ -n "$dec" ] && S8=$(echo "## Decisions (active; full text in .context/DECISIONS.md)"; printf '%s\n' "$dec")

		# 9. Map
		m=$(ctx_content < .context/MAP.md 2>/dev/null | grep -v '^#' )
		[ -n "$m" ] && S9=$(ctx_content < .context/MAP.md | sed '1s/^# /## /')
		order="1 2 3 4 5 6 7 8 9"
	fi

	# Assemble within the budget.
	size() { printf '%s\n' "$1" | wc -c | tr -d ' '; }
	total=$(size "$S0")
	for s in $order; do eval "v=\$S$s"; [ -n "$v" ] && total=$((total + $(size "$v") + 1)); done
	if [ "$total" -gt "$budget" ] && [ -z "$short" ]; then
		S1=$(printf '%s\n%s' "$S1" "- Full context is $total bytes, over the $budget-byte brief budget: older parts are shortened. Consider \"ctx compact\"." | awk 'NF')
	fi
	[ -n "$S1" ] && S1=$(printf '## Warnings\n%s' "$S1")
	printf '%s\n\n' "$S0"
	used=$(( $(size "$S0") + 1 )); omitted=""
	for s in $order; do
		eval "v=\$S$s; alt=\${A$s:-}"
		[ -n "$v" ] || continue
		sz=$(( $(size "$v") + 1 ))
		if [ $((used + sz)) -le "$budget" ]; then
			printf '%s\n\n' "$v"; used=$((used + sz)); continue
		fi
		if [ -n "$alt" ] && [ $((used + $(size "$alt") + 1)) -le "$budget" ]; then
			printf '%s\n\n' "$alt"; used=$((used + $(size "$alt") + 1)); continue
		fi
		room=$((budget - used - 160))
		if [ "$room" -gt 200 ]; then
			printf '%s\n' "$v" | LC_ALL=C awk -v max="$room" '{ n += length($0) + 1; if (n > max) exit; print }'
			echo "[… shortened to fit the brief budget]"; echo
			used=$budget
		else
			omitted="$omitted${omitted:+; }$(printf '%s\n' "$v" | head -n 1 | sed -e 's/^## //' -e 's/ [—(].*$//')"
		fi
	done
	[ -n "$omitted" ] && echo "[Omitted to fit the brief budget: $omitted — read them in .context/]"
	if [ -n "$hook" ] && { [ "$used" -ge "$budget" ] || [ -n "$omitted" ]; }; then
		echo "Full brief: sh .context/bin/ctx brief --no-fetch"
	fi
	return 0
}

# CTX_DEBUG=1 keeps stderr for diagnosing; normally hook output must stay clean.
run() {
	if [ "${CTX_DEBUG:-}" = 1 ]; then ( set -x; brief_main ) || echo "[ctx brief stopped early — read .context/ files directly]"
	else ( brief_main ) 2>/dev/null || echo "[ctx brief stopped early — read .context/ files directly]"; fi
}
if [ "$format" = codex ]; then
	printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$(run | ctx_json_string)"
else
	run
fi
exit 0
