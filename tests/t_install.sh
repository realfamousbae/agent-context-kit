# Phase 4: install.sh — fresh install next to existing files, idempotency, settings merge with
# jq / python / neither, --language, --update, --uninstall, hook chaining, initials, self-install.
. "$(dirname "$0")/lib.sh"

# A project that already has agent files of its own.
R="$T_TMP/r"; mkrepo "$R"
printf '# Project rules\n\n- Use tabs.\n' > "$R/AGENTS.md"
printf '# Claude notes\n\nPrefer small diffs.\n' > "$R/CLAUDE.md"
mkdir -p "$R/.claude"
cat > "$R/.claude/settings.json" <<'JSON'
{
  "permissions": { "allow": ["Bash(make test)"] },
  "hooks": {
    "Stop": [ { "hooks": [ { "type": "command", "command": "echo user-stop-hook" } ] } ]
  }
}
JSON
printf '*.png binary\n' > "$R/.gitattributes"
commit_all "$R" "project"

out=$(install_kit "$R" 2>&1); rc=$?
equals "install exit 0" "$rc" "0"
agents=$(cat "$R/AGENTS.md")
equals "ctx block is first in AGENTS.md" "$(head -n 1 "$R/AGENTS.md")" "<!-- ctx:begin v2 -->"
contains "user rules kept in AGENTS.md" "$agents" "- Use tabs."
equals "CLAUDE.md imports AGENTS.md first" "$(head -n 1 "$R/CLAUDE.md")" "@AGENTS.md"
contains "user text kept in CLAUDE.md" "$(cat "$R/CLAUDE.md")" "Prefer small diffs."
settings=$(cat "$R/.claude/settings.json")
contains "user permission kept" "$settings" "Bash(make test)"
contains "user Stop hook kept" "$settings" "user-stop-hook"
contains "our SessionStart hook added" "$settings" "ctx\\\" brief"
contains "our checkpoint hook added" "$settings" "checkpoint --hook"
contains "CTX_AGENT env added" "$settings" '"CTX_AGENT": "claude"'
check "settings.json is valid JSON" json_ok "$R/.claude/settings.json"
contains "user .gitattributes kept" "$(cat "$R/.gitattributes")" "*.png binary"
contains "kit .gitattributes block" "$(cat "$R/.gitattributes")" "# >>> agent-context-kit"
equals "hooks enabled" "$(git -C "$R" config core.hooksPath)" ".githooks"
equals "author set" "$(git -C "$R" config ctx.author)" "alice"
contains "AUTHORS registry" "$(cat "$R/.context/AUTHORS")" "alice aa"
check "slash commands installed" test -f "$R/.claude/commands/ctx-start.md"
check "both template languages present" test -f "$R/.context/templates/ru/templates/entry.md"
equals "exec bit in the index" "$(git -C "$R" ls-files -s .context/bin/ctx | cut -c1-6)" "100755"
contains "language defaults to en with a hint" "$out" "detect the project language"

# idempotent
before=$(snapshot "$R")
out2=$(install_kit "$R" 2>&1)
equals "second run changes nothing" "$(snapshot "$R")" "$before"
not_contains "second run reports no changes" "$out2" "  ~ "
not_contains "second run reports no additions" "$out2" "  + "

# BOOTSTRAP flow: first entry and commit pass the hooks
(CTX_AGENT=claude ctx "$R" entry --model m >/dev/null 2>&1); fill_draft "$R" claude >/dev/null
check "first commit after install passes the hooks" commit_all "$R" "Install agent-context-kit"

# python path and the no-tool path
for tool in python none; do
	P="$T_TMP/p-$tool"; mkrepo "$P"; mkdir -p "$P/.claude"
	printf '{\n    "model": "x"\n}\n' > "$P/.claude/settings.json"
	if [ $tool = python ]; then
		out=$(CTX_INSTALL_NO_JQ=1 install_kit "$P" 2>&1)
		contains "python merge keeps user key" "$(cat "$P/.claude/settings.json")" '"model": "x"'
		contains "python merge adds hooks" "$(cat "$P/.claude/settings.json")" "checkpoint --hook"
		before=$(snapshot "$P"); (CTX_INSTALL_NO_JQ=1 install_kit "$P" >/dev/null 2>&1)
		equals "python merge is idempotent" "$(snapshot "$P")" "$before"
		before=$(snapshot "$P"); install_kit "$P" >/dev/null 2>&1
		equals "jq after python changes nothing" "$(snapshot "$P")" "$before"
	else
		out=$(CTX_INSTALL_NO_JQ=1 CTX_INSTALL_NO_PYTHON=1 install_kit "$P" 2>&1)
		contains "no jq/python: prints the fragment" "$out" "Add this by hand"
		equals "no jq/python: user file untouched" "$(cat "$P/.claude/settings.json")" '{
    "model": "x"
}'
		Q="$T_TMP/q-none"; mkrepo "$Q"
		(CTX_INSTALL_NO_JQ=1 CTX_INSTALL_NO_PYTHON=1 install_kit "$Q" >/dev/null 2>&1)
		check "no jq/python, no settings: fragment copied" grep -q 'checkpoint --hook' "$Q/.claude/settings.json"
	fi
done

# --language ru
U="$T_TMP/ru"; mkrepo "$U"; install_kit "$U" --language ru --push-claims auto >/dev/null 2>&1
contains "ru TASKS headings" "$(cat "$U/.context/TASKS.md")" "## Сейчас <!-- ctx:now -->"
equals "kit.json language" "$(ctx "$U" config language)" "ru"
equals "kit.json push_claims" "$(ctx "$U" config push_claims)" "auto"
d=$(CTX_AGENT=codex ctx "$U" entry --model m 2>/dev/null)
contains "ru journal entry" "$(cat "$U/$d")" "## Сделано <!-- ctx:done -->"

# --update: kit files refreshed, project data untouched, new kit.json keys added
echo "# local hack" >> "$R/.context/bin/ctx-lib.sh"
echo "local edit" >> "$R/.context/PROTOCOL.md"
echo "- project fact" >> "$R/.context/MAP.md"
grep -v '"question_stale_days"' "$R/.context/kit.json" > "$T_TMP/k" && cat "$T_TMP/k" > "$R/.context/kit.json"
ctx "$R" config claim_stale_days 9 >/dev/null
out=$(install_kit "$R" 2>&1)
contains "plain re-run does not overwrite kit files" "$(tail -n 1 "$R/.context/bin/ctx-lib.sh")" "# local hack"
out=$(install_kit "$R" --update 2>&1)
not_contains "update restores ctx-lib.sh" "$(tail -n 1 "$R/.context/bin/ctx-lib.sh")" "# local hack"
not_contains "update restores PROTOCOL.md" "$(cat "$R/.context/PROTOCOL.md")" "local edit"
contains "update keeps MAP.md" "$(cat "$R/.context/MAP.md")" "- project fact"
equals "update keeps settings values" "$(ctx "$R" config claim_stale_days)" "9"
equals "update adds missing keys" "$(ctx "$R" config question_stale_days)" "3"
check "kit.json valid after update" json_ok "$R/.context/kit.json"

# --ci
install_kit "$R" --ci >/dev/null 2>&1
check "--ci installs the workflow" test -f "$R/.github/workflows/ctx.yml"

# --uninstall
out=$(install_kit "$R" --uninstall 2>&1)
equals "uninstall: AGENTS.md keeps user rules only" "$(cat "$R/AGENTS.md")" "# Project rules

- Use tabs."
contains "uninstall: CLAUDE.md kept (AGENTS.md still exists)" "$(cat "$R/CLAUDE.md")" "Prefer small diffs."
s=$(cat "$R/.claude/settings.json")
not_contains "uninstall: our hooks removed" "$s" ".context/bin/ctx"
contains "uninstall: user hook kept" "$s" "user-stop-hook"
not_contains "uninstall: env removed" "$s" "CTX_AGENT"
equals "uninstall: hooksPath unset" "$(git -C "$R" config core.hooksPath)" ""
check "uninstall: .context kept" test -f "$R/.context/TASKS.md"
not_contains "uninstall: gitattributes block removed" "$(cat "$R/.gitattributes")" "agent-context-kit"
check "uninstall: workflow removed" test ! -f "$R/.github/workflows/ctx.yml"
check "reinstall after uninstall" install_kit "$R"

# existing hooks in .git/hooks
H="$T_TMP/h"; mkrepo "$H"
printf '#!/bin/sh\necho old >> "%s/old.log"\n' "$T_TMP" > "$H/.git/hooks/pre-commit"; chmod +x "$H/.git/hooks/pre-commit"
out=$(install_kit "$H" 2>&1)
contains "existing hooks: warning" "$out" "--chain-hooks"
equals "existing hooks: hooksPath not changed" "$(git -C "$H" config core.hooksPath)" ""
contains "brief warns that hooks are off" "$(ctx "$H" brief)" "Git hooks are off"
install_kit "$H" --chain-hooks >/dev/null 2>&1
equals "chain: hooksPath set" "$(git -C "$H" config core.hooksPath)" ".githooks"
commit_all "$H" "install [no-ctx]"
contains "chain: old hook still runs" "$(cat "$T_TMP/old.log" 2>/dev/null)" "old"

# initials registry
I="$T_TMP/i"; mkrepo "$I"; install_kit "$I" >/dev/null 2>&1
git -C "$I" config --unset ctx.initials; git -C "$I" config --unset ctx.author
out=$( (cd "$I" && "$CTX_SHELL" "$KIT_DIR/install.sh" --author anna --initials aa) 2>&1); rc=$?
[ $rc -ne 0 ] && ok "taken initials are refused" || not_ok "taken initials are refused" "$out"
(cd "$I" && "$CTX_SHELL" "$KIT_DIR/install.sh" --author anna) >/dev/null 2>&1
contains "AUTHORS has both" "$(cat "$I/.context/AUTHORS")" "anna "
not_contains "anna did not get aa" "$(grep '^anna ' "$I/.context/AUTHORS")" "anna aa"

# self-install: the kit repo itself (dogfooding) — no legacy false alarm, kit files untouched
git clone -q "$KIT_DIR" "$T_TMP/kit" 2>/dev/null || cp -R "$KIT_DIR" "$T_TMP/kit"
K="$T_TMP/kit"
readme=$(cksum < "$K/README.md"); wf=$(cksum < "$K/.github/workflows/test.yml")
out=$(install_kit "$K" 2>&1); rc=$?
equals "self-install exit 0" "$rc" "0"
equals "self-install leaves README.md" "$(cksum < "$K/README.md")" "$readme"
equals "self-install leaves the kit workflow" "$(cksum < "$K/.github/workflows/test.yml")" "$wf"

finish
