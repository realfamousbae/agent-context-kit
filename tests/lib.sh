# Shared helpers for kit tests. Sourced by tests/t_*.sh; POSIX sh.
# shellcheck shell=sh disable=SC2034

set -u
KIT_DIR=$(cd "$(dirname "$0")/.." && pwd)
T_TMP=$(mktemp -d 2>/dev/null || { d="${TMPDIR:-/tmp}/ctx-test.$$"; mkdir -p "$d" && echo "$d"; })
T_PASS=0
T_FAIL=0
T_NAME=$(basename "$0" .sh)
trap 'rm -rf "$T_TMP"' EXIT

# Isolate from the developer's global git config (hooksPath, signing, templates).
HOME="$T_TMP/home"
export HOME
mkdir -p "$HOME"
cat > "$HOME/.gitconfig" <<CFG
[user]
	name = Test User
	email = test.user@example.invalid
[init]
	defaultBranch = main
[commit]
	gpgsign = false
[advice]
	detachedHead = false
CFG
unset CTX_AGENT CTX_MODEL CTX_SKIP GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE 2>/dev/null || true
CTX_NO_FETCH=1
CTX_SHELL=${TEST_SH:-sh}
export CTX_NO_FETCH CTX_SHELL

ok() { T_PASS=$((T_PASS + 1)); printf 'ok   %s: %s\n' "$T_NAME" "$1"; }
not_ok() {
	T_FAIL=$((T_FAIL + 1))
	printf 'FAIL %s: %s\n' "$T_NAME" "$1"
	[ $# -gt 1 ] && printf '%s\n' "$2" | sed 's/^/     | /'
	return 0
}

# check "description" cmd args... — passes when the command succeeds.
check() {
	_d=$1; shift
	if _o=$("$@" 2>&1); then ok "$_d"; else not_ok "$_d" "$_o"; fi
}
# check_fails "description" cmd args... — passes when the command fails.
check_fails() {
	_d=$1; shift
	if _o=$("$@" 2>&1); then not_ok "$_d" "$_o"; else ok "$_d"; fi
}
# contains "description" "haystack" "needle"
contains() {
	case $2 in *"$3"*) ok "$1" ;; *) not_ok "$1" "expected to contain: $3
--- got:
$2" ;; esac
}
not_contains() {
	case $2 in *"$3"*) not_ok "$1" "expected NOT to contain: $3
--- got:
$2" ;; *) ok "$1" ;; esac
}
equals() {
	if [ "$2" = "$3" ]; then ok "$1"; else not_ok "$1" "expected: $3
--- got:
$2"; fi
}

# mkrepo DIR — empty repo with one commit.
mkrepo() {
	mkdir -p "$1"
	git -C "$1" init -q
	git -C "$1" symbolic-ref HEAD refs/heads/main
	printf '# Demo\n' > "$1/README.md"
	git -C "$1" add README.md
	git -C "$1" commit -q -m "initial"
}

# install_kit DIR [args...] — run the installer into DIR as identity alice/aa unless overridden.
install_kit() {
	_t=$1; shift
	(cd "$_t" && "$CTX_SHELL" "$KIT_DIR/install.sh" --author alice --initials aa "$@")
}

# ctx DIR args... — run ctx inside DIR.
ctx() {
	_t=$1; shift
	(cd "$_t" && "$CTX_SHELL" .context/bin/ctx "$@")
}

finish() {
	printf '%s: %d passed, %d failed\n' "$T_NAME" "$T_PASS" "$T_FAIL"
	[ "$T_FAIL" -eq 0 ]
}

# kit_copy DIR [LANG] — minimal manual install of .context/ (no hooks, no agent files) for script tests.
kit_copy() {
	_l=${2:-en}
	mkdir -p "$1/.context/journal/archive" "$1/.context/templates"
	cp -R "$KIT_DIR/template/.context/." "$1/.context/"
	for _x in en ru; do
		mkdir -p "$1/.context/templates/$_x"
		cp -R "$KIT_DIR/template/i18n/$_x/." "$1/.context/templates/$_x/"
	done
	for _f in MAP.md DECISIONS.md GOTCHAS.md TASKS.md QUESTIONS.md; do
		cp "$KIT_DIR/template/i18n/$_l/$_f" "$1/.context/$_f"
	done
	(cd "$1" && "$CTX_SHELL" .context/bin/ctx config language "$_l" >/dev/null)
	git -C "$1" config ctx.author alice
	git -C "$1" config ctx.initials aa
}

# commit_all DIR MESSAGE — commit everything with hooks (if enabled).
commit_all() { git -C "$1" add -A && git -C "$1" commit -q -m "$2"; }

# write_entry DIR — fill the current draft of DIR's author with required sections and finish it.
fill_draft() {
	_d=$(cd "$1" && "$CTX_SHELL" .context/bin/ctx entry --path ${2:+--agent "$2"})
	[ -n "$_d" ] || return 1
	awk '{ print } /<!-- ctx:goal -->/ { print "- make the thing work" } /<!-- ctx:done -->/ { print "- did a thing" } /<!-- ctx:verified -->/ { print "tests" } /<!-- ctx:next -->/ { print "- next thing" }' \
		"$1/$_d" > "$1/$_d.tmp" && mv "$1/$_d.tmp" "$1/$_d"
	(cd "$1" && "$CTX_SHELL" .context/bin/ctx entry --finish ${2:+--agent "$2"} >/dev/null)
	printf '%s\n' "$_d"
}

is_windows() { case $(uname -s) in MINGW*|MSYS*|CYGWIN*) return 0 ;; esac; return 1; }

# json_ok FILE — valid JSON? (python3, python or jq; passes if none is installed)
json_ok() {
	if command -v python3 >/dev/null 2>&1; then python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1"
	elif command -v python >/dev/null 2>&1; then python -c 'import json,sys; json.load(open(sys.argv[1]))' "$1"
	elif command -v jq >/dev/null 2>&1; then jq . "$1" >/dev/null
	else return 0; fi
}

# enable_hooks DIR — copy the kit's git hooks and switch them on (what install.sh does).
enable_hooks() {
	mkdir -p "$1/.githooks"
	cp "$KIT_DIR/template/.githooks/pre-commit" "$KIT_DIR/template/.githooks/commit-msg" "$1/.githooks/"
	chmod +x "$1/.githooks/pre-commit" "$1/.githooks/commit-msg"
	git -C "$1" config core.hooksPath .githooks
}

# snapshot DIR — checksum of every file outside .git (to prove a re-run changed nothing).
snapshot() { (cd "$1" && find . -path ./.git -prune -o -type f -print | sort | while IFS= read -r f; do cksum "$f"; done; git config --local --list | sort); }

# hook_cmd FILE EVENT INDEX [KEY] — the command string of a hook in a settings/hooks JSON file.
hook_cmd() {
	for _py in python3 python; do
		if command -v "$_py" >/dev/null 2>&1 && "$_py" -c 'import json' >/dev/null 2>&1; then
			"$_py" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["hooks"][sys.argv[2]][int(sys.argv[3])]["hooks"][0][sys.argv[4]])' "$1" "$2" "$3" "${4:-command}"
			return
		fi
	done
	return 1
}
