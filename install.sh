#!/bin/sh
# agent-context-kit installer. POSIX sh; on Windows run it from Git Bash or through install.ps1.
#
#   sh install.sh [options]          install into the git repository of the current directory
#
#   --target DIR            repository to install into (default: the current one)
#   --language en|ru        language of the records in .context/ (default: en, or the existing one)
#   --push-claims ask|auto  push mode for `ctx claim` (default: ask)
#   --author NAME           this clone's author handle (git config ctx.author)
#   --initials XX           2–3 letters for IDs (git config ctx.initials), unique per person
#   --ci                    also install .github/workflows/ctx.yml
#   --chain-hooks           keep existing git hooks: ours run first, then the previous ones
#   --migrate               a legacy agent journal exists and you are migrating it (see MIGRATION.md)
#   --update                refresh kit-owned files (PROTOCOL.md, bin/, templates/, hooks) — never project data
#   --uninstall             remove the AGENTS.md block, hooks and settings; keeps .context/
#
# Idempotent: a second run changes nothing. Existing AGENTS.md, CLAUDE.md, .claude/settings.json and
# .gitattributes are merged into, never replaced. Exit codes: 0 ok, 1 error, 3 legacy journal found.

set -u
KIT=$(cd "$(dirname "$0")" && pwd)
TPL="$KIT/template"

target="" language="" push_claims="" author="" initials="" ci="" chain="" migrate="" mode=install
while [ $# -gt 0 ]; do
	case $1 in
		--target) target=${2:-}; shift ;;
		--language) language=${2:-}; shift ;;
		--push-claims) push_claims=${2:-}; shift ;;
		--author) author=${2:-}; shift ;;
		--initials) initials=${2:-}; shift ;;
		--ci) ci=1 ;;
		--chain-hooks) chain=1 ;;
		--migrate) migrate=1 ;;
		--update) mode=update ;;
		--uninstall) mode=uninstall ;;
		-h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "install.sh: unknown option $1 (see --help)" >&2; exit 1 ;;
	esac
	shift
done

say() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*"; }
die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }
changed() { say "  ~ $1"; }

[ -n "$target" ] && { cd "$target" || die "cannot cd to $target"; }
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository (use --target DIR)"
cd "$ROOT" || die "cannot cd to $ROOT"
case $language in ''|en|ru) ;; *) [ -d "$TPL/i18n/$language" ] || die "no templates for language '$language'" ;; esac
case $push_claims in ''|ask|auto|never) ;; *) die "--push-claims ask|auto" ;; esac
KIT_VERSION=$(sed -n 's/.*"kit_version"[ ]*:[ ]*"\([^"]*\)".*/\1/p' "$TPL/.context/kit.json")

# same_text FILE CONTENT_FILE — equal ignoring CR (so Windows checkouts do not cause rewrites)
same_text() { [ -f "$1" ] && [ "$(tr -d '\r' < "$1")" = "$(tr -d '\r' < "$2")" ]; }

# put SRC DEST [force] — copy if DEST is missing (or differs, with force); report.
put() {
	if [ ! -f "$2" ]; then
		mkdir -p "$(dirname "$2")" && cp "$1" "$2" && say "  + $2"
	elif [ -n "${3:-}" ] && ! same_text "$2" "$1"; then
		cp "$1" "$2" && changed "$2"
	fi
}

# replace_block FILE BEGIN_RE END_RE BLOCKFILE WHERE — insert or refresh a marked block (WHERE: top|bottom).
replace_block() {
	local file begin end block where tmp
	file=$1 begin=$2 end=$3 block=$4 where=$5
	tmp=$(mktemp) || die "mktemp failed"
	if [ -f "$file" ] && grep -q -- "$begin" "$file"; then
		awk -v b="$begin" -v e="$end" -v bf="$block" '
			BEGIN { while ((getline l < bf) > 0) blk = blk l "\n" }
			!skip && index($0, b) { printf "%s", blk; skip = 1; next }
			skip { if (index($0, e)) skip = 0; next }
			{ sub(/\r$/, ""); print }' "$file" > "$tmp"
	elif [ -f "$file" ] && [ "$where" = top ]; then
		{ cat "$block"; echo; tr -d '\r' < "$file"; } > "$tmp"
	elif [ -f "$file" ]; then
		{ tr -d '\r' < "$file"; [ -s "$file" ] && [ -n "$(tail -c 1 "$file" | tr -d '\r\n')" ] && echo; cat "$block"; } > "$tmp"
	else
		cp "$block" "$tmp"
	fi
	if same_text "$file" "$tmp"; then rm -f "$tmp"; return 0; fi
	if [ -f "$file" ]; then changed "$file"; else say "  + $file"; fi
	cat "$tmp" > "$file"; rm -f "$tmp"
}

# remove_block FILE BEGIN END — drop a marked block; delete the file if nothing else is left.
remove_block() {
	local tmp
	[ -f "$1" ] && grep -q -- "$2" "$1" || return 0
	tmp=$(mktemp) || die "mktemp failed"
	awk -v b="$2" -v e="$3" '
		!skip && index($0, b) { skip = 1; drop_blank = 1; next }
		skip { if (index($0, e)) skip = 0; next }
		drop_blank && /^[ \t\r]*$/ { drop_blank = 0; next }
		{ drop_blank = 0; print }' "$1" > "$tmp"
	if [ -z "$(tr -d ' \t\r\n' < "$tmp")" ]; then rm -f "$1" "$tmp"; say "  - $1"
	else cat "$tmp" > "$1"; rm -f "$tmp"; changed "$1"; fi
}

# --- .claude/settings.json: merge our hooks and env with jq, python, or print instructions --------

PY_MERGE='
import json, os, sys
path, frag_path, mode = sys.argv[1], sys.argv[2], sys.argv[3]
def ours(h): return ".context/bin/ctx" in (h.get("command") or "")
data = {}
if os.path.exists(path) and open(path, encoding="utf-8").read().strip():
    data = json.load(open(path, encoding="utf-8"))
frag = json.load(open(frag_path, encoding="utf-8"))
before = json.dumps(data, sort_keys=True)
hooks = data.get("hooks") or {}
for ev in sorted(set(hooks) | set(frag["hooks"])):
    kept = []
    for g in hooks.get(ev, []):
        hs = [h for h in g.get("hooks", []) if not ours(h)]
        if hs:
            g = dict(g); g["hooks"] = hs; kept.append(g)
    if mode == "install":
        kept += frag["hooks"].get(ev, [])
    if kept: hooks[ev] = kept
    else: hooks.pop(ev, None)
if hooks: data["hooks"] = hooks
else: data.pop("hooks", None)
env = data.get("env") or {}
for k, v in frag["env"].items():
    if mode == "install": env.setdefault(k, v)
    elif env.get(k) == v: env.pop(k)
if env: data["env"] = env
else: data.pop("env", None)
if json.dumps(data, sort_keys=True) == before:
    sys.exit(0)
if mode == "uninstall" and not data:
    os.remove(path); print("removed"); sys.exit(0)
with open(path, "w", encoding="utf-8", newline="\n") as f:
    json.dump(data, f, indent=2, ensure_ascii=False); f.write("\n")
print("changed")
'

JQ_MERGE='
def ours: (.command // "") | contains(".context/bin/ctx");
def strip: map(.hooks = ((.hooks // []) | map(select(ours | not)))) | map(select((.hooks | length) > 0));
($frag[0]) as $f
| (.hooks // {}) as $h
| ([($h | keys[]), ($f.hooks | keys[])] | unique) as $evs
| .hooks = (reduce $evs[] as $e ({};
    ((($h[$e] // []) | strip) + (if $mode == "install" then ($f.hooks[$e] // []) else [] end)) as $g
    | if ($g | length) > 0 then .[$e] = $g else . end))
| if (.hooks | length) == 0 then del(.hooks) else . end
| .env = (reduce ($f.env | to_entries[]) as $kv ((.env // {});
    if $mode == "install" then (if has($kv.key) then . else .[$kv.key] = $kv.value end)
    elif .[$kv.key] == $kv.value then del(.[$kv.key]) else . end))
| if (.env | length) == 0 then del(.env) else . end
'

find_python() {
	[ "${CTX_INSTALL_NO_PYTHON:-}" = 1 ] && return 1
	for p in python3 python; do
		command -v "$p" >/dev/null 2>&1 && "$p" -c 'import json' >/dev/null 2>&1 && { echo "$p"; return 0; }
	done
	command -v py >/dev/null 2>&1 && py -3 -c 'import json' >/dev/null 2>&1 && { echo "py -3"; return 0; }
	return 1
}

merge_settings() { # merge_settings install|uninstall
	local f frag py tmp out
	f=.claude/settings.json frag="$TPL/.claude/settings.json"
	if [ "$1" = uninstall ] && [ ! -f "$f" ]; then return 0; fi
	if [ "${CTX_INSTALL_NO_JQ:-}" != 1 ] && command -v jq >/dev/null 2>&1; then
		mkdir -p .claude
		tmp=$(mktemp) || die "mktemp failed"
		if [ -s "$f" ]; then cp "$f" "$tmp.in"; else echo '{}' > "$tmp.in"; fi
		if jq --arg mode "$1" --slurpfile frag "$frag" "$JQ_MERGE" "$tmp.in" > "$tmp" 2>/dev/null; then
			if [ "$(jq -S -c . "$tmp.in")" != "$(jq -S -c . "$tmp")" ]; then
				if [ "$1" = uninstall ] && [ "$(jq -c . "$tmp")" = "{}" ]; then rm -f "$f"; say "  - $f"
				elif [ -s "$f" ]; then cat "$tmp" > "$f"; changed "$f"
				else cat "$tmp" > "$f"; say "  + $f"; fi
			elif [ ! -f "$f" ] && [ "$1" = install ]; then cat "$tmp" > "$f"; say "  + $f"
			fi
			rm -f "$tmp" "$tmp.in"; return 0
		fi
		rm -f "$tmp" "$tmp.in"
		warn "jq could not parse $f — trying python"
	fi
	if py=$(find_python); then
		mkdir -p .claude
		# shellcheck disable=SC2086
		if out=$($py -c "$PY_MERGE" "$f" "$frag" "$1" 2>&1); then
			case $out in changed) changed "$f" ;; removed) say "  - $f" ;; esac
			return 0
		fi
		warn "python could not merge $f: $out"
	fi
	if [ "$1" = install ]; then
		if [ ! -f "$f" ] || [ ! -s "$f" ]; then mkdir -p .claude; cp "$frag" "$f"; say "  + $f"; return 0; fi
		grep -q '.context/bin/ctx' "$f" && return 0
		warn "neither jq nor python is available to merge $f. Add this by hand (hooks and env):"
		cat "$frag"
	else
		grep -q '.context/bin/ctx' "$f" && warn "remove the hooks with .context/bin/ctx and env.CTX_AGENT from $f by hand"
	fi
	return 0
}

# --- legacy journal detection ------------------------------------------------

legacy_journal() {
	[ -d docs/ai-journal ] && echo "docs/ai-journal/"
	for f in NOTES.md CHANGES.md; do
		[ -f "$f" ] && grep -q -i -E 'claude|codex|agent|агент' "$f" && echo "$f"
	done
	if [ -f AGENTS.md ] && awk '/<!-- ctx:begin/ { s = 1 } /<!-- ctx:end -->/ { s = 0; next } !s' AGENTS.md |
		grep -q -i -E '^#+ .*(journal|log of changes|changelog|журнал)'; then
		echo "AGENTS.md (journal rules)"
	fi
}

# --- identity ------------------------------------------------------------------

slug() { printf '%s' "$1" | tr 'A-Z' 'a-z' | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//'; }

setup_identity() {
	local a i owner cand
	a=$author
	[ -n "$a" ] || a=$(git config ctx.author 2>/dev/null)
	[ -n "$a" ] || a=$(git config user.name 2>/dev/null)
	a=$(slug "$a")
	[ -n "$a" ] || die "cannot determine the author: pass --author NAME"
	i=$(printf '%s' "$initials" | tr 'A-Z' 'a-z')
	[ -n "$i" ] || i=$(git config ctx.initials 2>/dev/null)
	if [ -z "$i" ]; then
		for cand in "$(echo "$a" | sed 's/[^a-z]//g' | cut -c1-2)" \
			"$(echo "$a" | sed 's/[^a-z]//g' | sed 's/^\(.\).*\(.\)$/\1\2/')" \
			"$(echo "$a" | sed 's/[^a-z]//g' | cut -c1-3)"; do
			owner=$(awk -v i="$cand" '$2 == i { print $1; exit }' .context/AUTHORS 2>/dev/null)
			if [ -z "$owner" ] || [ "$owner" = "$a" ]; then i=$cand; break; fi
		done
		[ -n "$i" ] || die "initials for '$a' are taken in .context/AUTHORS: pass --initials XX"
	fi
	case $i in [a-z][a-z]|[a-z][a-z][a-z]) ;; *) die "initials must be 2–3 letters a-z (got '$i')" ;; esac
	owner=$(awk -v i="$i" '$2 == i { print $1; exit }' .context/AUTHORS 2>/dev/null)
	[ -z "$owner" ] || [ "$owner" = "$a" ] || die "initials '$i' already belong to '$owner' (.context/AUTHORS): pass other --initials"
	git config ctx.author "$a" 2>/dev/null || warn "cannot write git config (read-only .git?): run git config ctx.author $a"
	git config ctx.initials "$i" 2>/dev/null || true
	if ! awk -v a="$a" '$1 == a { f = 1 } END { exit !f }' .context/AUTHORS 2>/dev/null; then
		[ -f .context/AUTHORS ] || printf '# author initials — one line per person, append only (IDs use the initials)\n' > .context/AUTHORS
		printf '%s %s\n' "$a" "$i" >> .context/AUTHORS
		changed ".context/AUTHORS ($a $i)"
	fi
	say "Identity: ctx.author=$a, ctx.initials=$i"
}

# --- hooks path ----------------------------------------------------------------

setup_hooks_path() {
	local cur common old
	cur=$(git config core.hooksPath 2>/dev/null)
	[ "$cur" = .githooks ] && return 0
	common=$(git rev-parse --git-common-dir 2>/dev/null)
	case $common in /*|?:*) ;; *) common="$ROOT/$common" ;; esac
	if [ -n "$cur" ]; then old=$cur
	else
		old=""
		for h in "$common"/hooks/*; do
			[ -f "$h" ] || continue
			case $h in *.sample) continue ;; esac
			old="$common/hooks"; break
		done
	fi
	if [ -n "$old" ] && [ -z "$chain" ]; then
		warn "existing git hooks in $old would stop running if core.hooksPath changed."
		warn "Re-run with --chain-hooks (ours run first, then pre-commit/commit-msg from $old), or merge them by hand."
		warn "Until then the ctx hooks are OFF in this clone (ctx brief will say so)."
		return 0
	fi
	if [ -n "$old" ]; then
		git config ctx.chainHooks "$old" 2>/dev/null
		say "Previous hooks chained: $old (pre-commit, commit-msg)."
		for h in "$old"/*; do
			[ -f "$h" ] || continue
			case $(basename "$h") in *.sample|pre-commit|commit-msg) continue ;; esac
			warn "$(basename "$h") in $old is not chained and will not run; copy it into .githooks/ if you need it."
		done
	fi
	if git config core.hooksPath .githooks 2>/dev/null; then say "Git hooks on: core.hooksPath=.githooks"
	else warn "cannot write git config (read-only .git?): run git config core.hooksPath .githooks"; fi
}

# --- uninstall -------------------------------------------------------------------

if [ "$mode" = uninstall ]; then
	say "Uninstalling agent-context-kit from $ROOT (.context/ is kept)"
	remove_block AGENTS.md '<!-- ctx:begin' '<!-- ctx:end -->'
	if [ ! -f AGENTS.md ] && [ -f CLAUDE.md ]; then
		tmp=$(mktemp); tr -d '\r' < CLAUDE.md | grep -v -x '@AGENTS.md' > "$tmp"
		if [ -z "$(tr -d ' \t\r\n' < "$tmp")" ]; then rm -f CLAUDE.md; say "  - CLAUDE.md"; else cat "$tmp" > CLAUDE.md; changed CLAUDE.md; fi
		rm -f "$tmp"
	fi
	merge_settings uninstall
	for c in "$TPL"/.claude/commands/*.md; do
		[ -f ".claude/commands/$(basename "$c")" ] && rm -f ".claude/commands/$(basename "$c")" && say "  - .claude/commands/$(basename "$c")"
	done
	rmdir .claude/commands .claude 2>/dev/null
	for h in pre-commit commit-msg; do
		[ -f ".githooks/$h" ] && grep -q 'agent-context-kit' ".githooks/$h" && rm -f ".githooks/$h" && say "  - .githooks/$h"
	done
	rmdir .githooks 2>/dev/null
	remove_block .gitattributes '# >>> agent-context-kit' '# <<< agent-context-kit'
	[ -f .github/workflows/ctx.yml ] && grep -q 'agent-context-kit' .github/workflows/ctx.yml && rm -f .github/workflows/ctx.yml && say "  - .github/workflows/ctx.yml"
	if [ "$(git config core.hooksPath 2>/dev/null)" = .githooks ]; then
		prev=$(git config ctx.chainHooks 2>/dev/null)
		common=$(git rev-parse --git-common-dir 2>/dev/null)
		case $common in /*|?:*) ;; *) common="$ROOT/$common" ;; esac
		if [ -n "$prev" ] && [ "$prev" != "$common/hooks" ]; then git config core.hooksPath "$prev"; say "core.hooksPath restored to $prev"
		else git config --unset core.hooksPath; say "core.hooksPath unset"; fi
	fi
	git config --unset ctx.chainHooks 2>/dev/null
	say "Done. .context/ and git config ctx.author/ctx.initials are left in place."
	exit 0
fi

# --- install / update ----------------------------------------------------------------

if [ ! -d .context ] && [ -z "$migrate" ] && [ "$mode" = install ]; then
	legacy=$(legacy_journal)
	if [ -n "$legacy" ]; then
		say "Found an existing agent journal — not installing a second protocol on top of it:"
		printf '%s\n' "$legacy" | sed 's/^/  /'
		say "Follow MIGRATION.md in the kit ($KIT/MIGRATION.md):"
		say "  it starts with: sh $KIT/install.sh --migrate [same options]"
		exit 3
	fi
fi

say "agent-context-kit $KIT_VERSION → $ROOT ($mode)"
force=""
[ "$mode" = update ] && force=1
fresh=""
[ -f .context/kit.json ] || fresh=1

# .gitattributes first, so files staged below are normalised
replace_block .gitattributes '# >>> agent-context-kit' '# <<< agent-context-kit' "$KIT/snippets/gitattributes" bottom

# kit-owned files
mkdir -p .context/journal/archive .context/bin/cmd || die "cannot create .context/"
put "$TPL/.context/PROTOCOL.md" .context/PROTOCOL.md "$force"
for f in "$TPL"/.context/bin/*; do [ -f "$f" ] && put "$f" ".context/bin/$(basename "$f")" "$force"; done
for f in "$TPL"/.context/bin/cmd/*; do put "$f" ".context/bin/cmd/$(basename "$f")" "$force"; done
for d in "$TPL"/i18n/*/; do
	l=$(basename "$d")
	for f in MAP.md DECISIONS.md GOTCHAS.md TASKS.md QUESTIONS.md templates/entry.md; do
		put "$d$f" ".context/templates/$l/$f" "$force"
	done
done
[ -f .context/journal/archive/.gitkeep ] || : > .context/journal/archive/.gitkeep

# kit.json: new keys get defaults, existing values stay
if [ -n "$fresh" ]; then
	cp "$TPL/.context/kit.json" .context/kit.json && say "  + .context/kit.json"
else
	awk -F'"' '/^  "/ { print $2 }' "$TPL/.context/kit.json" | while IFS= read -r k; do
		grep -q "\"$k\"" .context/kit.json || {
			v=$(grep "\"$k\"" "$TPL/.context/kit.json" | sed -e 's/^[^:]*:[ ]*//' -e 's/,[ ]*$//')
			sh .context/bin/ctx config "$k" "$(printf '%s' "$v" | tr -d '"')" >/dev/null && changed ".context/kit.json ($k)"
		}
	done
fi
cur_version=$(sed -n 's/.*"kit_version"[ ]*:[ ]*"\([^"]*\)".*/\1/p' .context/kit.json)
if [ "$cur_version" != "$KIT_VERSION" ]; then
	if [ "$mode" = update ] || [ -z "$cur_version" ]; then
		tmp=$(mktemp); sed "s/\"kit_version\": *\"[^\"]*\"/\"kit_version\": \"$KIT_VERSION\"/" .context/kit.json > "$tmp" && cat "$tmp" > .context/kit.json; rm -f "$tmp"
		changed ".context/kit.json (kit_version $KIT_VERSION)"
	else
		warn "installed kit is $cur_version, this kit is $KIT_VERSION: run with --update to refresh kit files"
	fi
fi
lang_now=$(sed -n 's/.*"language"[ ]*:[ ]*"\([^"]*\)".*/\1/p' .context/kit.json)
if [ -n "$language" ] && [ "$language" != "$lang_now" ]; then
	sh .context/bin/ctx config language "$language" >/dev/null && changed ".context/kit.json (language $language)"
	lang_now=$language
fi
if [ -n "$push_claims" ]; then
	[ "$(sh .context/bin/ctx config push_claims)" = "$push_claims" ] ||
		{ sh .context/bin/ctx config push_claims "$push_claims" >/dev/null && changed ".context/kit.json (push_claims $push_claims)"; }
fi

# project data: only if missing, in the project's language
for f in MAP.md DECISIONS.md GOTCHAS.md TASKS.md QUESTIONS.md; do
	put "$TPL/i18n/$lang_now/$f" ".context/$f"
done

# agent entry points
replace_block AGENTS.md '<!-- ctx:begin' '<!-- ctx:end -->' "$KIT/snippets/agents-block.md" top
if [ ! -f CLAUDE.md ]; then
	printf '@AGENTS.md\n' > CLAUDE.md && say "  + CLAUDE.md"
elif ! tr -d '\r' < CLAUDE.md | grep -q -x '@AGENTS.md'; then
	tmp=$(mktemp); { printf '@AGENTS.md\n\n'; cat CLAUDE.md; } > "$tmp" && cat "$tmp" > CLAUDE.md; rm -f "$tmp"; changed "CLAUDE.md (@AGENTS.md)"
fi
merge_settings install
for c in "$TPL"/.claude/commands/*.md; do put "$c" ".claude/commands/$(basename "$c")" "$force"; done

# git hooks (never overwrite someone else's hook of the same name)
for h in pre-commit commit-msg; do
	if [ -f ".githooks/$h" ] && ! grep -q 'agent-context-kit' ".githooks/$h"; then
		warn ".githooks/$h exists and is not ours — left untouched; merge it with $TPL/.githooks/$h by hand"
		continue
	fi
	put "$TPL/.githooks/$h" ".githooks/$h" "$force"
done
if [ -n "$ci" ]; then
	if [ -f .github/workflows/ctx.yml ] && ! grep -q 'agent-context-kit' .github/workflows/ctx.yml; then
		warn ".github/workflows/ctx.yml exists and is not ours — left untouched"
	else
		put "$TPL/.github/workflows/ctx.yml" .github/workflows/ctx.yml "$force"
	fi
fi

# exec bits: in the work tree and in the index, so they survive clones on every OS
exe=".context/bin/ctx .githooks/pre-commit .githooks/commit-msg"
for f in .context/bin/cmd/*.sh; do exe="$exe $f"; done
for f in $exe; do [ -f "$f" ] && chmod +x "$f" 2>/dev/null; done
# shellcheck disable=SC2086
if ! git add --chmod=+x -- $exe 2>/dev/null; then
	warn "could not stage the scripts (read-only .git?). Ask the user to run: git add --chmod=+x $exe"
fi

setup_identity
setup_hooks_path

say "Language of records: $lang_now$([ -z "$language" ] && [ -n "$fresh" ] && echo ' (default — detect the project language per BOOTSTRAP.md, then: sh .context/bin/ctx config language <code>)')"
if [ -n "$migrate" ]; then
	say "Migration mode: now follow MIGRATION.md (sh .context/bin/ctx migrate <legacy files>)."
fi
[ -n "$fresh" ] && say "Next: fill in .context/MAP.md, DECISIONS.md, TASKS.md and the first journal entry (BOOTSTRAP.md), show the user the diff."
say "Done. Review with: git status && git diff"
exit 0
