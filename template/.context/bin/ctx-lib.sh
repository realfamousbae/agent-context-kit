# ctx-lib.sh — shared functions for ctx subcommands. POSIX sh; sourced, not executed.
# Rules: no GNU/BSD-only flags, no bashisms except `local`, paths relative to the repo root.
# shellcheck shell=sh

# Byte semantics everywhere: awk implementations disagree on multibyte characters otherwise
# (gawk counts characters in UTF-8 locales, mawk and BWK awk count bytes).
LC_ALL=C
export LC_ALL
# Git Bash (MSYS2) rewrites arguments that look like POSIX paths when it starts native programs;
# "origin/x:.context/TASKS.md" would be mangled into a Windows path list. ctx only passes relative
# paths to git, so conversion is switched off.
MSYS_NO_PATHCONV=1
MSYS2_ARG_CONV_EXCL='*'
export MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL

ctx_say() { printf '%s\n' "$*"; }
ctx_err() { printf 'ctx: %s\n' "$*" >&2; }
ctx_die() { ctx_err "$*"; exit 1; }

# --- repository -----------------------------------------------------------

# ctx_init — set CTX_ROOT, CTX_DIR and friends; dies outside a repo with .context/.
ctx_init() {
	CTX_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ctx_die "not inside a git repository"
	CTX_DIR="$CTX_ROOT/.context"
	[ -d "$CTX_DIR" ] || ctx_die "no .context/ in $CTX_ROOT — install agent-context-kit first"
	CTX_JSON="$CTX_DIR/kit.json"
	CTX_JOURNAL="$CTX_DIR/journal"; export CTX_JOURNAL
	CTX_GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
	case $CTX_GIT_DIR in /*|?:*) ;; *) CTX_GIT_DIR="$CTX_ROOT/$CTX_GIT_DIR" ;; esac
	cd "$CTX_ROOT" || ctx_die "cannot cd to $CTX_ROOT"
}

# ctx_state_dir — per-worktree scratch dir under .git; prints nothing if it cannot be created.
ctx_state_dir() {
	mkdir -p "$CTX_GIT_DIR/ctx" 2>/dev/null && [ -w "$CTX_GIT_DIR/ctx" ] && printf '%s\n' "$CTX_GIT_DIR/ctx"
}

ctx_tmp() {
	mktemp 2>/dev/null || {
		_t="${TMPDIR:-/tmp}/ctx.$$.$(awk 'BEGIN { srand(); print int(rand() * 1000000) }')"
		: > "$_t" && printf '%s\n' "$_t"
	}
}

# ctx_timeout SECONDS cmd... — run cmd, kill it after SECONDS (no `timeout` on macOS).
ctx_timeout() {
	local secs pid watcher rc
	secs=$1; shift
	"$@" &
	pid=$!
	( sleep "$secs"; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
	watcher=$!
	wait "$pid"; rc=$?
	kill "$watcher" 2>/dev/null
	wait "$watcher" 2>/dev/null
	return $rc
}

# ctx_git_net git-args... — network git with no prompts and a hard timeout.
ctx_git_net() {
	GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=5}" \
		ctx_timeout "$(ctx_cfg fetch_timeout_seconds 8)" git "$@"
}

ctx_has_remote() { [ -n "$(git remote 2>/dev/null)" ]; }

# --- kit.json (flat: one "key": value per line) ----------------------------

# ctx_cfg KEY DEFAULT — value from kit.json without quotes, or DEFAULT.
ctx_cfg() {
	local v
	v=$(awk -v k="\"$1\"" '
		index($0, k ":") {
			sub(/^[^:]*:[ \t]*/, ""); sub(/,[ \t]*$/, ""); sub(/[ \t\r]*$/, "")
			gsub(/^"|"$/, ""); print; exit
		}' "$CTX_JSON" 2>/dev/null)
	if [ -n "$v" ]; then printf '%s\n' "$v"; else printf '%s\n' "$2"; fi
}

# ctx_cfg_int KEY DEFAULT — like ctx_cfg but guaranteed to be a non-negative integer.
ctx_cfg_int() {
	local v
	v=$(ctx_cfg "$1" "$2")
	case $v in ''|*[!0-9]*) v=$2 ;; esac
	printf '%s\n' "$v"
}

# ctx_cfg_set KEY RAW_JSON_VALUE — replace or add a key, keeping the file flat.
ctx_cfg_set() {
	local tmp
	tmp=$(ctx_tmp) || return 1
	awk -v k="\"$1\"" -v v="$2" '
		{ lines[NR] = $0 }
		index($0, k ":") { found = NR }
		END {
			if (found) {
				comma = (lines[found] ~ /,[ \t\r]*$/) ? "," : ""
				lines[found] = "  " k ": " v comma
				for (i = 1; i <= NR; i++) print lines[i]
				exit
			}
			for (i = 1; i <= NR; i++) {
				if (lines[i] ~ /^}/) {
					# previous non-empty line needs a trailing comma
					for (j = i - 1; j > 0; j--) if (lines[j] !~ /^[ \t]*$/) break
					if (j > 0 && lines[j] !~ /[{,][ \t\r]*$/) lines[j] = lines[j] ","
					for (p = 1; p < i; p++) print lines[p]
					print "  " k ": " v
					for (p = i; p <= NR; p++) print lines[p]
					exit
				}
			}
		}' "$CTX_JSON" > "$tmp" && cat "$tmp" > "$CTX_JSON"
	rm -f "$tmp"
}

ctx_lang() {
	local l
	l=$(ctx_cfg language en)
	[ -f "$CTX_DIR/templates/$l/templates/entry.md" ] || l=en
	printf '%s\n' "$l"
}

ctx_template_dir() { printf '%s\n' "$CTX_DIR/templates/$(ctx_lang)"; }

# --- identity --------------------------------------------------------------

ctx_slug() {
	printf '%s' "$1" | tr 'A-Z' 'a-z' | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//'
}

ctx_author() {
	local a
	a=$(git config ctx.author 2>/dev/null)
	[ -n "$a" ] || a=$(ctx_slug "$(git config user.name 2>/dev/null)")
	[ -n "$a" ] || a=unknown
	ctx_slug "$a"
}

ctx_initials() {
	local i
	i=$(git config ctx.initials 2>/dev/null | tr 'A-Z' 'a-z')
	case $i in [a-z][a-z]|[a-z][a-z][a-z]) ;; *) i=$(ctx_author | sed 's/[^a-z]//g' | cut -c1-2) ;; esac
	[ ${#i} -ge 2 ] || i="${i}xx"
	printf '%s\n' "$i" | cut -c1-3
}

# ctx_agent [VALUE] — normalised agent name: claude, codex, human or another single word.
ctx_agent() {
	local a
	a=${1:-${CTX_AGENT:-human}}
	a=$(ctx_slug "$a")
	case $a in claude-code|claude-*|claudecode) a=claude ;; codex-*|openai-codex) a=codex ;; '') a=human ;; esac
	printf '%s\n' "$a" | tr -d '-'
}

ctx_model() { printf '%s\n' "${1:-${CTX_MODEL:-unknown}}"; }

ctx_me() { printf '%s/%s\n' "$(ctx_author)" "$(ctx_agent "${1:-}")"; }

# --- time ------------------------------------------------------------------

ctx_today() { date +%Y-%m-%d; }
ctx_today_compact() { date +%Y%m%d; }
ctx_stamp_utc() { date -u +%Y%m%d-%H%MZ; }
ctx_now_local() { date '+%Y-%m-%d %H:%M %z' | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/'; }

# ctx_days_between YYYY-MM-DD|YYYYMMDD YYYY-MM-DD|YYYYMMDD — whole days from $1 to $2.
ctx_days_between() {
	awk -v a="$1" -v b="$2" '
		function dn(s,   y, m, d) {
			gsub(/-/, "", s); y = substr(s, 1, 4) + 0; m = substr(s, 5, 2) + 0; d = substr(s, 7, 2) + 0
			if (m <= 2) { y--; m += 12 }
			return 365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (m - 3) + 2) / 5) + d
		}
		BEGIN { print dn(b) - dn(a) }'
}

# --- IDs -------------------------------------------------------------------

# ctx_next_id TYPE — next free ID for this author today, e.g. T-20261022-aa-3.
ctx_next_id() {
	local prefix max
	prefix="$1-$(ctx_today_compact)-$(ctx_initials)-"
	max=$(find "$CTX_DIR" -path "$CTX_DIR/bin" -prune -o -path "$CTX_DIR/templates" -prune -o -type f -name '*.md' ! -name PROTOCOL.md -print 2>/dev/null |
		while IFS= read -r f; do cat "$f"; done |
		awk -v p="$prefix" '
			{
				s = $0
				while ((i = index(s, p)) > 0) {
					s = substr(s, i + length(p)); n = s; sub(/[^0-9].*$/, "", n)
					if (n != "" && n + 0 > max) max = n + 0
				}
			}
			END { print max + 0 }')
	printf '%s%s\n' "$prefix" $((max + 1))
}

# --- markdown sections -----------------------------------------------------

# ctx_section FILE KEY — body of the "## … <!-- ctx:KEY -->" section, without the heading.
ctx_section() {
	awk -v a="<!-- ctx:$2 -->" '
		/^##[^#]/ { if (on) exit; if (index($0, a)) { on = 1; next } }
		on { print }' "$1" 2>/dev/null
}

# ctx_content — filter stdin to meaningful lines (no blanks, no comment-only lines).
ctx_content() {
	awk '
		/^[ \t\r]*$/ { next }
		/^[ \t]*<!--.*-->[ \t\r]*$/ { next }
		{ print }'
}

# ctx_frontmatter FILE KEY
ctx_frontmatter() {
	awk -v k="$2" '
		NR == 1 && /^---/ { on = 1; next }
		on && /^---/ { exit }
		on && index($0, k ":") == 1 { sub(/^[^:]*:[ \t]*/, ""); sub(/[ \t\r]*$/, ""); print; exit }' "$1" 2>/dev/null
}

# --- journal ---------------------------------------------------------------

# Journal file name: YYYYMMDD-HHMM[SS]Z-<author>-<agent>.md (agent has no dashes).
ctx_entry_author() { basename "$1" .md | sed -e 's/^[0-9]*-[0-9]*Z-//' -e 's/-[^-]*$//'; }
ctx_entry_agent() { basename "$1" .md | sed 's/^.*-//'; }

# ctx_entries — local journal entries (not archive), oldest first, relative paths.
ctx_entries() {
	for f in .context/journal/*.md; do [ -f "$f" ] && printf '%s\n' "$f"; done
}

ctx_is_draft() { [ "$(ctx_frontmatter "$1" status)" = draft ]; }

# ctx_my_draft [AGENT] — newest draft of this author (and agent, if given).
ctx_my_draft() {
	local me f found
	me=$(ctx_author); found=""
	for f in $(ctx_entries); do
		[ "$(ctx_entry_author "$f")" = "$me" ] || continue
		[ -z "${1:-}" ] || [ "$(ctx_entry_agent "$f")" = "$1" ] || continue
		ctx_is_draft "$f" && found=$f
	done
	[ -n "$found" ] && printf '%s\n' "$found"
}

# ctx_my_last_done — newest finished entry of this author.
ctx_my_last_done() {
	local me f found
	me=$(ctx_author); found=""
	for f in $(ctx_entries); do
		[ "$(ctx_entry_author "$f")" = "$me" ] || continue
		ctx_is_draft "$f" || found=$f
	done
	[ -n "$found" ] && printf '%s\n' "$found"
}

# ctx_entry_missing FILE — print required sections that are empty.
ctx_entry_missing() {
	local k
	for k in "done" verified next; do
		[ -n "$(ctx_section "$1" "$k" | ctx_content)" ] || printf '%s\n' "$k"
	done
}

# ctx_entry_has_content FILE — anything written in any section?
ctx_entry_has_content() {
	[ -n "$(awk '/^---/ { fm++; next } fm >= 2 && !/^##/' "$1" | ctx_content)" ]
}

# --- tasks and claims ------------------------------------------------------

# ctx_tasks_in SECTION [FILE] — task lines of a TASKS.md section (now, next, blocked, done); FILE "-" is stdin.
ctx_tasks_in() {
	ctx_section "${2:-.context/TASKS.md}" "$1" | awk '/^- \[[ xX]\] [TDGQ]-/'
}

# ctx_task_field LINE FIELD — owner | agent | since | area | id
ctx_task_field() {
	printf '%s\n' "$1" | awk -v f="$2" '
		{
			if (f == "id") { match($0, /[T]-[0-9]+-[a-z]+-[0-9]+/); print substr($0, RSTART, RLENGTH); exit }
			if (f == "owner" || f == "agent") {
				if (match($0, / @[a-z0-9-]+\/[a-z0-9]+/)) {
					s = substr($0, RSTART + 2, RLENGTH - 2); split(s, p, "/")
					print (f == "owner" ? p[1] : p[2])
				}
				exit
			}
			if (f == "since") { if (match($0, /since [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) print substr($0, RSTART + 6, 10); exit }
			if (f == "area") {
				i = index($0, "area:"); if (!i) exit
				s = substr($0, i + 5); out = ""
				while (match(s, /`[^`]+`/)) { out = out (out == "" ? "" : " ") substr(s, RSTART + 1, RLENGTH - 2); s = substr(s, RSTART + RLENGTH) }
				print out; exit
			}
		}'
}

# ctx_glob_prefix PATTERN — literal part before the first glob character.
ctx_glob_prefix() { printf '%s\n' "$1" | sed 's/[][*?].*$//'; }

# ctx_path_in_area PATH AREA_ITEM — does a file path fall into one area item?
ctx_path_in_area() {
	case $2 in
		*/) case $1 in "$2"*) return 0 ;; esac ;;
		*[][*?]*) # shellcheck disable=SC2254
			case $1 in $2) return 0 ;; esac ;;
		*) [ "$1" = "$2" ] && return 0; case $1 in "$2"/*) return 0 ;; esac ;;
	esac
	return 1
}

# ctx_items_overlap A B — can two area items cover the same file? Conservative for globs.
ctx_items_overlap() {
	local pa pb
	ctx_path_in_area "$1" "$2" && return 0
	ctx_path_in_area "$2" "$1" && return 0
	case "$1$2" in
		*[][*?]*)
			pa=$(ctx_glob_prefix "$1"); pb=$(ctx_glob_prefix "$2")
			case $pa in "$pb"*) return 0 ;; esac
			case $pb in "$pa"*) return 0 ;; esac ;;
	esac
	return 1
}

# ctx_areas_overlap "A1 A2" "B1 B2" — print the first overlapping pair.
ctx_areas_overlap() {
	local a b
	set -f
	for a in $1; do
		for b in $2; do
			if ctx_items_overlap "$a" "$b"; then set +f; printf '%s ~ %s\n' "$a" "$b"; return 0; fi
		done
	done
	set +f
	return 1
}

# ctx_claim_age_days LINE — days since the claim or the owner's latest journal entry, whichever is newer.
ctx_claim_age_days() {
	local since owner last f d
	since=$(ctx_task_field "$1" since)
	[ -n "$since" ] || { echo 0; return; }
	owner=$(ctx_task_field "$1" owner)
	last=$(echo "$since" | tr -d '-')
	for f in $(ctx_entries); do
		[ "$(ctx_entry_author "$f")" = "$owner" ] || continue
		d=$(basename "$f" | cut -c1-8)
		[ "$d" -gt "$last" ] 2>/dev/null && last=$d
	done
	ctx_days_between "$last" "$(ctx_today_compact)"
}

ctx_claim_is_stale() {
	[ "$(ctx_claim_age_days "$1")" -gt "$(ctx_cfg_int claim_stale_days 3)" ]
}

# ctx_remote_claims — Now lines from origin/* branches that are not in the local TASKS.md, prefixed "branch<TAB>".
ctx_remote_claims() {
	local b
	for b in $(ctx_remote_branches); do
		git show "$b:.context/TASKS.md" 2>/dev/null | ctx_tasks_in now - | while IFS= read -r l; do
			grep -F -x -q -- "$l" .context/TASKS.md 2>/dev/null || printf '%s\t%s\n' "$b" "$l"
		done
	done
}

# ctx_remote_branches — up to remote_branches_max origin/* refs, newest first, excluding HEAD aliases.
ctx_remote_branches() {
	git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/remotes/origin 2>/dev/null |
		awk -v max="$(ctx_cfg_int remote_branches_max 20)" '$0 != "origin/HEAD" && $0 != "origin" && n < max { print; n++ }'
}

# --- commit helpers ---------------------------------------------------------

# ctx_commit_paths MESSAGE PATH... — commit only these paths; never fails hard.
ctx_commit_paths() {
	local msg
	msg=$1; shift
	git add -- "$@" 2>/dev/null || return 1
	git commit -q -m "$msg" -- "$@" >/dev/null 2>&1
}

# ctx_push_mode FLAG — auto | ask (flag > git config ctx.pushClaims > kit.json).
ctx_push_mode() {
	local m
	m=$1
	[ -n "$m" ] || m=$(git config ctx.pushClaims 2>/dev/null)
	[ -n "$m" ] || m=$(ctx_cfg push_claims ask)
	case $m in auto|ask|never) ;; *) m=ask ;; esac
	printf '%s\n' "$m"
}

# ctx_maybe_push MODE WHAT — push the current branch according to MODE.
ctx_maybe_push() {
	local branch
	branch=$(git symbolic-ref --short -q HEAD 2>/dev/null)
	if ! ctx_has_remote || [ -z "$branch" ]; then
		ctx_say "No remote or detached HEAD: the $2 stays local. Others will not see it until you push."
		return 0
	fi
	case $1 in
		auto)
			if ctx_git_net push -q origin "HEAD:$branch" >/dev/null 2>&1; then
				ctx_say "Pushed the $2 to origin/$branch."
			else
				ctx_say "WARNING: push failed (offline, sandbox or rejected). The $2 is a local commit; others do not see it."
				ctx_say "Ask the user to run: git pull --rebase && git push origin HEAD:$branch"
			fi ;;
		ask)
			ctx_say "push_claims=ask: show the user this command and run it only after they agree:"
			ctx_say "  git push origin HEAD:$branch" ;;
		never) ctx_say "The $2 is committed locally; it travels with your next push." ;;
	esac
}

# --- questions --------------------------------------------------------------

# ctx_questions FILE MODE "ADDRESSEES" — open question blocks (question line + its answers).
#   MODE: mine (addressed to one of ADDRESSEES), others (not), all.
ctx_questions() {
	awk -v mode="$2" -v to=" $3 " '
		function flush() {
			if (q != "" && !closed) {
				mine = index(to, " " addr " ") > 0
				if (mode == "all" || (mode == "mine" && mine) || (mode == "others" && !mine)) printf "%s", q
			}
			q = ""; closed = 0
		}
		/^##[^#]/ { flush(); on = index($0, "<!-- ctx:open -->") > 0; next }
		!on { next }
		/^- Q-/ {
			flush(); q = $0 "\n"
			addr = ""; if (match($0, /· @[^ ]+/)) addr = substr($0, RSTART + 3, RLENGTH - 3)
			if (index($0, "✅")) closed = 1
			next
		}
		q != "" && /^[ \t]+/ { q = q $0 "\n"; if (index($0, "✅")) closed = 1; next }
		{ flush() }
		END { flush() }' "$1" 2>/dev/null
}

# ctx_my_addressees [AGENT] — names that count as "me" for questions.
ctx_my_addressees() {
	local a
	a=$(ctx_agent "${1:-}")
	if [ -n "${1:-}${CTX_AGENT:-}" ]; then
		printf '@%s @%s @all\n' "$(ctx_author)" "$a"
	else
		printf '@%s @all @claude @codex\n' "$(ctx_author)"
	fi
}

# --- history ------------------------------------------------------------------

# ctx_since_install — "SHA..HEAD" from the commit that added .context/kit.json (older history is not
# expected to follow the protocol); empty when the kit is not committed yet.
ctx_since_install() {
	local c
	c=$(git log --diff-filter=A --format=%H -- .context/kit.json 2>/dev/null | tail -n 1)
	[ -n "$c" ] || return 0
	if git rev-parse -q --verify "$c^" >/dev/null 2>&1; then printf '%s^..HEAD\n' "$c"; else echo HEAD; fi
}

# ctx_commit_classes GIT-LOG-ARGS... — one line per non-merge commit:
#   sha TAB class TAB author TAB date TAB subject TAB top-level dirs
# class: journal (code + entry), context (only .context/), noctx ([no-ctx]), skip (Ctx-Skip trailer),
#        missing (code without an entry — hooks bypassed or not installed).
ctx_commit_classes() {
	local noctx skip
	noctx=$(git log --no-merges --format=%h --fixed-strings --grep='[no-ctx]' "$@" 2>/dev/null | tr '\n' ' ')
	skip=$(git log --no-merges --format=%h --grep='^Ctx-Skip:' "$@" 2>/dev/null | tr '\n' ' ')
	git log --no-merges --date=short --format="$(printf '\001')%h%x09%an%x09%ad%x09%s" --name-only "$@" 2>/dev/null |
		awk -v noctx=" $noctx " -v skip=" $skip " '
			function out() {
				if (sha == "") return
				if (!code) c = "context"
				else if (index(noctx, " " sha " ")) c = "noctx"
				else if (index(skip, " " sha " ")) c = "skip"
				else if (journal) c = "journal"
				else c = "missing"
				print sha "\t" c "\t" rest "\t" dirs
				sha = ""
			}
			/^\001/ {
				out()
				s = substr($0, 2); i = index(s, "\t"); sha = substr(s, 1, i - 1); rest = substr(s, i + 1)
				code = 0; journal = 0; dirs = ""; delete seen; next
			}
			/^$/ { next }
			{
				if ($0 ~ /^\.context\//) { if ($0 ~ /^\.context\/journal\/[^\/]*\.md$/) journal = 1; next }
				code = 1
				d = $0; if (index(d, "/")) sub(/\/.*$/, "/", d)
				if (!(d in seen) && length(dirs) < 60) { seen[d] = 1; dirs = dirs (dirs == "" ? "" : " ") d }
			}
			END { out() }'
}
