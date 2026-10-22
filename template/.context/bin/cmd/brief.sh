#!/bin/sh
# ctx brief [--short] [--budget BYTES] [--no-fetch] [--agent A]
# Start-of-session summary within a byte budget, highest priority first:
#   warnings, questions to me, tasks in progress, gotchas, others' entries since my last one (all branches),
#   code commits without a journal entry, recent entries, decisions index, map.
# --short (after context compaction): warnings, questions, tasks, gotchas and my current draft.
# It never fails: any error ends the output early, the exit code is always 0.
# shellcheck source=../ctx-lib.sh
CTX_BIN=${CTX_BIN:-$(cd "$(dirname "$0")/.." && pwd)}
. "$CTX_BIN/ctx-lib.sh"
GIT_OPTIONAL_LOCKS=0
export GIT_OPTIONAL_LOCKS

short="" budget="" fetch=1 agent_arg=""
while [ $# -gt 0 ]; do
	case $1 in
		--short) short=1 ;;
		--budget) budget=${2:-}; shift ;;
		--no-fetch) fetch="" ;;
		--agent) agent_arg=${2:-}; shift ;;
	esac
	shift
done
[ "${CTX_NO_FETCH:-}" = 1 ] && fetch=""

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
	W=$(mktemp -d 2>/dev/null) || { W="${TMPDIR:-/tmp}/ctx-brief.$$"; mkdir -p "$W"; } || return 0
	trap 'rm -rf "$W"' EXIT INT TERM

	me=$(ctx_author)
	agent=$(ctx_agent "$agent_arg")
	[ -n "$agent_arg$CTX_AGENT" ] || agent="(agent unknown)"
	lang=$(ctx_lang)
	branch=$(git symbolic-ref --short -q HEAD 2>/dev/null || echo "detached HEAD")
	if [ -n "$short" ]; then budget=${budget:-$(ctx_cfg_int brief_short_budget_bytes 8000)}
	else budget=${budget:-$(ctx_cfg_int brief_budget_bytes 24000)}; fi
	case $budget in ''|*[!0-9]*) budget=24000 ;; esac

	{
		printf '# ctx brief — %s, branch %s, you are %s/%s\n' "$(basename "$CTX_ROOT")" "$branch" "$me" "$agent"
		printf 'Write everything in .context/ in language "%s". Rules: .context/PROTOCOL.md.\n\n' "$lang"
	} > "$W/0"

	# 1. Warnings
	{
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
	} > "$W/1"

	# 2. Questions addressed to me
	ctx_questions .context/QUESTIONS.md mine "$(ctx_my_addressees "$agent_arg")" > "$W/2.body"
	nother=$(ctx_questions .context/QUESTIONS.md others "$(ctx_my_addressees "$agent_arg")" | grep -c '^- Q-')
	{
		if [ -s "$W/2.body" ]; then echo "## Open questions for you — answer: ctx ask --answer Q-… \"…\""; cat "$W/2.body"; fi
		[ "${nother:-0}" -gt 0 ] && echo "($nother other open question(s): ctx ask --list)"
	} > "$W/2"

	# 3. Tasks in progress and blocked
	{
		now=$(ctx_tasks_in now)
		remote=$(ctx_remote_claims)
		blocked=$(ctx_tasks_in blocked)
		if [ -n "$now$remote$blocked" ]; then
			echo "## Tasks in progress — claim yours before editing: ctx claim T-… --area \"…\""
			[ -n "$now" ] && printf '%s\n' "$now" | while IFS= read -r l; do
				o=$(ctx_task_field "$l" owner); tag=""
				case $l in (*" — paused "*) tag=" [paused]" ;; *)
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
	} > "$W/3"

	# 4. Active gotchas
	g=$(awk '/^- G-/ && !/\[resolved/' .context/GOTCHAS.md 2>/dev/null)
	[ -n "$g" ] && { echo "## Gotchas (active)"; printf '%s\n' "$g"; } > "$W/4"

	if [ -n "$short" ]; then
		d=$(ctx_my_draft "$( [ -n "$agent_arg$CTX_AGENT" ] && ctx_agent "$agent_arg")" 2>/dev/null)
		if [ -n "$d" ]; then
			{ echo "## Your journal draft: $d (keep filling it in)"; render_entry "$(basename "$d")" "" "" < "$d"; } > "$W/5"
		else
			echo "## No journal draft of yours — start one: ctx entry --agent <claude|codex> --model <id>" > "$W/5"
		fi
		order="1 2 3 4 5"
	else
		last=$(ctx_my_last_done); lastname=""
		[ -n "$last" ] && lastname=$(basename "$last")
		# 5. Others' entries after my last one, incl. other branches
		: > "$W/5.full"; : > "$W/5.key"; : > "$W/shown"
		for f in $(ctx_entries | awk -v last=".context/journal/$lastname" -v any="${lastname:-1}" 'any == 1 || $0 > last'); do
			[ "$(ctx_entry_author "$f")" = "$me" ] && continue
			ctx_is_draft "$f" && continue
			basename "$f" >> "$W/shown"
		done
		tail -n 10 "$W/shown" > "$W/shown.tmp"; cat "$W/shown.tmp" > "$W/shown"
		while IFS= read -r n; do
			render_entry "$n" "" "" < ".context/journal/$n" >> "$W/5.full"
			render_entry "$n" "" 1 < ".context/journal/$n" >> "$W/5.key"
		done < "$W/shown"
		refs=$(ctx_remote_branches)
		for b in main master; do
			[ "$b" != "$branch" ] && git rev-parse -q --verify "refs/heads/$b" >/dev/null 2>&1 && refs="$refs $b"
		done
		for r in $refs; do
			git ls-tree --name-only "$r" .context/journal/ 2>/dev/null | grep '\.md$' | while IFS= read -r p; do
				n=$(basename "$p")
				[ -f ".context/journal/$n" ] || [ -f ".context/journal/archive/$n" ] && continue
				grep -F -x -q "$n" "$W/shown" 2>/dev/null && continue
				echo "$n" >> "$W/shown"
				git show "$r:$p" 2>/dev/null > "$W/e"
				render_entry "$n" " [branch $r]" "" < "$W/e" >> "$W/5.full"
				render_entry "$n" " [branch $r]" 1 < "$W/e" >> "$W/5.key"
			done
		done
		if [ -s "$W/5.full" ]; then
			hdr="## New from others since your last entry${lastname:+ ($lastname)}"
			{ echo "$hdr"; cat "$W/5.full"; } > "$W/5"
			{ echo "$hdr (key sections only)"; cat "$W/5.key"; } > "$W/5.alt"
		fi

		# 6. Code commits without a journal entry since my last entry
		range="-n 30 $(ctx_since_install)"
		if [ -n "$last" ]; then
			c=$(git log -1 --format=%H -- "$last" 2>/dev/null)
			[ -n "$c" ] && range="$c..HEAD"
		fi
		# shellcheck disable=SC2086
		miss=$(ctx_commit_classes $range | awk -F '\t' '$2 == "missing"' | head -n 15)
		[ -n "$miss" ] && {
			echo "## Commits with code but no journal entry (ask their authors or check the diff)"
			printf '%s\n' "$miss" | awk -F '\t' '{ printf "- %s %s %s — %s [%s]\n", $1, $4, $3, $5, $6 }'
		} > "$W/6"

		# 7. Recent entries not shown above
		: > "$W/7.full"; : > "$W/7.key"
		ctx_entries | while IFS= read -r f; do ctx_is_draft "$f" || basename "$f"; done |
			tail -n "$(ctx_cfg_int recent_entries 5)" | while IFS= read -r n; do
				grep -F -x -q "$n" "$W/shown" 2>/dev/null && continue
				render_entry "$n" "" "" < ".context/journal/$n" >> "$W/7.full"
				render_entry "$n" "" 1 < ".context/journal/$n" >> "$W/7.key"
			done
		if [ -s "$W/7.full" ]; then
			{ echo "## Recent journal entries"; cat "$W/7.full"; } > "$W/7"
			{ echo "## Recent journal entries (key sections only)"; cat "$W/7.key"; } > "$W/7.alt"
		fi

		# 8. Decisions index (active only)
		awk '
			/^### D-/ { if (h != "" && !sup) print h; h = $0; sub(/^### /, "- ", h); sup = 0; next }
			/^#/ { if (h != "" && !sup) print h; h = ""; next }
			h != "" && /superseded/ { sup = 1 }
			END { if (h != "" && !sup) print h }' .context/DECISIONS.md 2>/dev/null > "$W/8.body"
		[ -s "$W/8.body" ] && { echo "## Decisions (active; full text in .context/DECISIONS.md)"; cat "$W/8.body"; } > "$W/8"

		# 9. Map
		m=$(ctx_content < .context/MAP.md 2>/dev/null | grep -v '^#' )
		[ -n "$m" ] && ctx_content < .context/MAP.md | sed '1s/^# /## /' > "$W/9"
		order="1 2 3 4 5 6 7 8 9"
	fi

	# Assemble within the budget.
	size() { if [ -f "$1" ]; then wc -c < "$1" | tr -d ' '; else echo 0; fi; }
	total=0
	for s in 0 $order; do total=$((total + $(size "$W/$s"))); done
	if [ "$total" -gt "$budget" ] && [ -z "$short" ]; then
		echo "- Full context is $total bytes, over the $budget-byte brief budget: older parts are shortened. Consider \"ctx compact\"." >> "$W/1"
	fi
	[ -s "$W/1" ] && { echo "## Warnings"; cat "$W/1"; } > "$W/1.out" && mv "$W/1.out" "$W/1"
	cat "$W/0"
	used=$(size "$W/0")
	for s in $order; do
		[ -s "$W/$s" ] || continue
		sz=$(size "$W/$s")
		if [ $((used + sz)) -le "$budget" ]; then
			cat "$W/$s"; echo; used=$((used + sz + 1)); continue
		fi
		if [ -s "$W/$s.alt" ] && [ $((used + $(size "$W/$s.alt"))) -le "$budget" ]; then
			cat "$W/$s.alt"; echo; used=$((used + $(size "$W/$s.alt") + 1)); continue
		fi
		room=$((budget - used - 160))
		if [ "$room" -gt 200 ]; then
			LC_ALL=C awk -v max="$room" '{ n += length($0) + 1; if (n > max) exit; print }' "$W/$s"
			echo "[… shortened to fit the brief budget]"; echo
			used=$budget
		else
			omitted="$omitted${omitted:+; }$(head -n 1 "$W/$s" | sed -e 's/^## //' -e 's/ [—(].*$//')"
		fi
	done
	[ -n "${omitted:-}" ] && echo "[Omitted to fit the brief budget: $omitted — read them in .context/]"
	return 0
}

# CTX_DEBUG=1 keeps stderr for diagnosing; normally hook output must stay clean.
if [ "${CTX_DEBUG:-}" = 1 ]; then ( set -x; brief_main ) || echo "[ctx brief stopped early — read .context/ files directly]"
else ( brief_main ) 2>/dev/null || echo "[ctx brief stopped early — read .context/ files directly]"; fi
exit 0
