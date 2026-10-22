#!/bin/sh
# shellcheck source=../ctx-lib.sh
CTX_BIN=${CTX_BIN:-$(cd "$(dirname "$0")/.." && pwd)}
. "$CTX_BIN/ctx-lib.sh"
# ctx claim — claim a task and its area in .context/TASKS.md, commit, push per push_claims.
#   ctx claim T-… --area "src/upload/ tests/test_upload*" [--push|--no-push|--no-commit] [--force] [--agent A]
#   ctx claim --new "Title" --area "…"
#   ctx claim --done T-…  |  ctx claim --pause T-…
ctx_init
T=.context/TASKS.md
[ -f "$T" ] || ctx_die "missing $T — run install.sh"

mode=claim id="" title="" area="" push_flag="" force="" agent_arg="" commit=1
while [ $# -gt 0 ]; do
	case $1 in
		--new) title=${2:-}; shift ;;
		--area) area=${2:-}; shift ;;
		--done) mode="done"; id=${2:-}; shift ;;
		--pause) mode=pause; id=${2:-}; shift ;;
		--push) push_flag=auto ;;
		--no-push) push_flag=never ;;
		--no-commit) commit="" ;;
		--force) force=1 ;;
		--agent) agent_arg=${2:-}; shift ;;
		T-*) id=$1 ;;
		*) ctx_die "unknown argument: $1 (see ctx help)" ;;
	esac
	shift
done
me=$(ctx_author)
agent=$(ctx_agent "$agent_arg")
today=$(ctx_today)
area=$(printf '%s' "$area" | tr ',' ' ' | sed 's/`//g')

# task_title LINE — title text without checkbox, ID and machine fields.
task_title() {
	printf '%s\n' "$1" | sed -e 's/^- \[[ xX]\] [TDGQ]-[0-9]*-[a-z]*-[0-9]* *//' -e 's/ — @[a-z0-9-]*\/.*$//' \
		-e 's/ — since [0-9-]*.*$//' -e 's/ — area:.*$//' -e 's/ — paused.*$//' -e 's/ — waiting for:.*$//'
}

# rewrite_tasks ID NEWLINE SECTION — drop the task line everywhere, add NEWLINE to SECTION
# (top of Now, bottom of other sections).
rewrite_tasks() {
	local tmp
	tmp=$(ctx_tmp) || ctx_die "cannot create a temp file"
	awk -v id="$1 " -v nl="$2" -v sec="<!-- ctx:$3 -->" '
		/^- \[[ xX]\] / && index($0, id) { next }
		{ l[++n] = $0 }
		END {
			h = 0; e = n + 1
			for (i = 1; i <= n; i++) {
				if (l[i] ~ /^##[^#]/) { if (h) { e = i; break } if (index(l[i], sec)) h = i }
			}
			if (!h) { for (i = 1; i <= n; i++) print l[i]; print nl; exit }
			at = h
			if (sec != "<!-- ctx:now -->") for (i = h + 1; i < e; i++) if (l[i] !~ /^[ \t\r]*$/) at = i
			for (i = 1; i <= n; i++) { print l[i]; if (i == at) print nl }
		}' "$T" > "$tmp" && cat "$tmp" > "$T"
	rm -f "$tmp"
}

save() {
	[ -n "$commit" ] || { ctx_say "Not committed (--no-commit)."; return 0; }
	if ctx_commit_paths "$1" "$T"; then
		ctx_say "Committed: $1"
		[ "$mode" = claim ] && ctx_maybe_push "$(ctx_push_mode "$push_flag")" "claim"
	else
		ctx_say "WARNING: TASKS.md is updated but not committed (read-only .git, sandbox, or hook failure)."
		ctx_say "Ask the user to run: git add $T && git commit -m \"$1\" -- $T"
	fi
	return 0
}

find_line() { grep -- "^- \[[ xX]\] $1 " "$T" | head -n 1; }

case $mode in
	done|pause)
		[ -n "$id" ] || ctx_die "usage: ctx claim --$mode T-…"
		line=$(find_line "$id"); [ -n "$line" ] || ctx_die "no task $id in $T"
		t=$(task_title "$line")
		if [ "$mode" = "done" ]; then
			rewrite_tasks "$id" "- [x] $id $t — @$me/$agent — $today" "done"
			ctx_say "$id → Done"
		else
			rewrite_tasks "$id" "- [ ] $id $t — @$me/$agent — paused $today" now
			ctx_say "$id paused; area released"
		fi
		save "ctx: $mode $id"
		exit 0 ;;
esac

if [ -n "$title" ]; then
	[ -z "$id" ] || ctx_die "use either T-… or --new, not both"
	id=$(ctx_next_id T)
	line=""
else
	[ -n "$id" ] || ctx_die 'usage: ctx claim T-… --area "…"  or  ctx claim --new "Title" --area "…"'
	line=$(find_line "$id")
	[ -n "$line" ] || ctx_die "no task $id in $T (create one with --new)"
	title=$(task_title "$line")
	owner=$(ctx_task_field "$line" owner)
	if [ -n "$owner" ] && [ "$owner" != "$me" ] && ctx_tasks_in now | grep -F -q -- "$id " &&
		! printf '%s' "$line" | grep -q ' — paused '; then
		if ctx_claim_is_stale "$line"; then
			[ -n "$force" ] || ctx_die "$id is claimed by @$owner (stale). Ask first: ctx ask @$owner \"May I take $id?\" — then --force"
		else
			[ -n "$force" ] || ctx_die "$id is claimed by @$owner. Ask first: ctx ask @$owner \"…\""
		fi
	fi
	[ -n "$area" ] || area=$(ctx_task_field "$line" area)
fi
[ -n "$area" ] || ctx_die "--area is required: the files or directories you will edit"

# Overlaps with other people's live claims, here and on origin/* branches.
conflicts=$( { ctx_tasks_in now | sed 's/^/local	/'; ctx_remote_claims; } | while IFS='	' read -r where l; do
	o=$(ctx_task_field "$l" owner)
	[ -n "$o" ] && [ "$o" != "$me" ] || continue
	case $l in (*" — paused "*) continue ;; esac
	a=$(ctx_task_field "$l" area)
	[ -n "$a" ] || continue
	if pair=$(ctx_areas_overlap "$area" "$a"); then
		st=""; ctx_claim_is_stale "$l" && st=" (stale)"
		printf '  %s @%s%s on %s: %s\n' "$(ctx_task_field "$l" id)" "$o" "$st" "$where" "$pair"
	fi
done)
if [ -n "$conflicts" ] && [ -z "$force" ]; then
	ctx_err "area overlaps other claims — do not edit these files yet:"
	printf '%s\n' "$conflicts" >&2
	ctx_err "Ask the owner (ctx ask @owner \"…\"), tell the user, and re-run with --force only after agreement."
	exit 1
fi

fmt_area=$(set -f; for a in $area; do printf '`%s`, ' "$a"; done | sed 's/, $//')
new="- [ ] $id $title — @$me/$agent — since $today — area: $fmt_area"
rewrite_tasks "$id" "$new" now
ctx_say "Claimed $id: $fmt_area"
save "ctx: claim $id"
exit 0
