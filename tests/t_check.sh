# Phase 2: ctx check modes, called directly (the hooks are tested in t_hooks).
. "$(dirname "$0")/lib.sh"
R="$T_TMP/r"; mkrepo "$R"; kit_copy "$R"
ctx "$R" config push_claims never >/dev/null
commit_all "$R" "setup"

# --staged
echo a > "$R/app.py"; git -C "$R" add app.py
check_fails "staged: code without entry rejected" ctx "$R" check --staged
CTX_AGENT=claude ctx "$R" entry --model m >/dev/null 2>&1
d=$(ctx "$R" entry --path --agent claude); git -C "$R" add "$d"
out=$(ctx "$R" check --staged 2>&1)
contains "staged: draft named in the message" "$out" "still a draft"
fill_draft "$R" claude >/dev/null; git -C "$R" add "$d"
check "staged: finished entry accepted" ctx "$R" check --staged
git -C "$R" commit -q -m "app"
echo ctx-only >> "$R/.context/MAP.md"; git -C "$R" add .context/MAP.md
check "staged: .context-only change accepted" ctx "$R" check --staged
git -C "$R" commit -q -m "map"
echo b >> "$R/app.py"; git -C "$R" add app.py
: > "$R/.git/MERGE_HEAD"
check "staged: merge commit accepted" ctx "$R" check --staged
rm -f "$R/.git/MERGE_HEAD"
check "staged: CTX_SKIP=1 accepted" env CTX_SKIP=1 sh -c "cd '$R' && '$CTX_SHELL' .context/bin/ctx check --staged"

# --commit-msg
printf 'fix typo [no-ctx]\n' > "$T_TMP/msg"
check "commit-msg: [no-ctx] accepted" ctx "$R" check --commit-msg "$T_TMP/msg"
printf 'real change\n' > "$T_TMP/msg"
check_fails "commit-msg: code without entry rejected" ctx "$R" check --commit-msg "$T_TMP/msg"
check "commit-msg: CTX_SKIP accepted" env CTX_SKIP=1 sh -c "cd '$R' && '$CTX_SHELL' .context/bin/ctx check --commit-msg '$T_TMP/msg'"
contains "commit-msg: CTX_SKIP trailer added" "$(cat "$T_TMP/msg")" "Ctx-Skip: CTX_SKIP"
printf 'msg [no-ctx]\n\nCo-Authored-By: Claude <noreply@anthropic.com>\nCo-authored-by: Sam <sam@example.invalid>\n\xf0\x9f\xa4\x96 Generated with [Claude Code](https://claude.com/claude-code)\n' > "$T_TMP/msg"
ctx "$R" check --commit-msg "$T_TMP/msg"
m=$(cat "$T_TMP/msg")
not_contains "AI co-author stripped" "$m" "anthropic"
not_contains "generated-with line stripped" "$m" "Generated with"
contains "human co-author kept" "$m" "Co-authored-by: Sam"
ctx "$R" config strip_ai_coauthor false >/dev/null
printf 'msg [no-ctx]\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n' > "$T_TMP/msg"
ctx "$R" check --commit-msg "$T_TMP/msg"
contains "strip_ai_coauthor=false keeps it" "$(cat "$T_TMP/msg")" "anthropic"
git -C "$R" reset -q; git -C "$R" checkout -q -- app.py

# --pre-commit: secrets and personal data
printf -- '- G-x · key sk-abcdefghijklmnopqrstuvwx in config\n' >> "$R/.context/GOTCHAS.md"; git -C "$R" add .context/GOTCHAS.md
check_fails "pre-commit: API key rejected" ctx "$R" check --pre-commit
check "pre-commit: CTX_SKIP_SECRETS bypass" env CTX_SKIP_SECRETS=1 sh -c "cd '$R' && '$CTX_SHELL' .context/bin/ctx check --pre-commit"
git -C "$R" checkout -q -- .context/GOTCHAS.md 2>/dev/null; git -C "$R" reset -q; git -C "$R" checkout -q -- .context/GOTCHAS.md
printf -- '- ask jane.roe@example.org about it\n' >> "$R/.context/MAP.md"; git -C "$R" add .context/MAP.md
check_fails "pre-commit: email rejected" ctx "$R" check --pre-commit
git -C "$R" reset -q; git -C "$R" checkout -q -- .context/MAP.md
printf -- '- password: hunter22\n' >> "$R/.context/MAP.md"; git -C "$R" add .context/MAP.md
check_fails "pre-commit: password rejected" ctx "$R" check --pre-commit
git -C "$R" reset -q; git -C "$R" checkout -q -- .context/MAP.md
printf -- '- ghp_ prefix is mentioned, @alice/claude is not an email\n' >> "$R/.context/MAP.md"; git -C "$R" add .context/MAP.md
check "pre-commit: harmless text accepted" ctx "$R" check --pre-commit
git -C "$R" commit -q -m "map [no-ctx]"
# claim warning (does not block)
git -C "$R" config ctx.author bob; git -C "$R" config ctx.initials bb
ctx "$R" claim --new "Bob's area" --area "lib/" >/dev/null
git -C "$R" config ctx.author alice; git -C "$R" config ctx.initials aa
mkdir -p "$R/lib"; echo x > "$R/lib/a.py"; git -C "$R" add lib/a.py
out=$(ctx "$R" check --pre-commit 2>&1); rc=$?
equals "pre-commit: claim overlap does not block" "$rc" "0"
contains "pre-commit: claim overlap warns" "$out" "claimed by @bob"
git -C "$R" reset -q; rm -rf "$R/lib"

# --soft (Claude Code Stop hook)
soft() { printf '%s' "$1" | (cd "$R" && CTX_AGENT=claude "$CTX_SHELL" .context/bin/ctx check --soft) 2>&1; echo "rc=$?"; }
equals "soft: clean tree → silent" "$(soft '{"session_id":"s1","stop_hook_active":false}')" "rc=0"
echo y > "$R/new.py"
out=$(soft '{"session_id":"s1","stop_hook_active":false}')
contains "soft: code without draft → reminder" "$out" "no journal draft"
contains "soft: reminder exits 2" "$out" "rc=2"
equals "soft: only once per session" "$(soft '{"session_id":"s1","stop_hook_active":false}')" "rc=0"
contains "soft: new session reminded again" "$(soft '{"session_id":"s2","stop_hook_active":false}')" "rc=2"
equals "soft: stop_hook_active → never blocks" "$(soft '{"session_id":"s3", "stop_hook_active": true}')" "rc=0"
CTX_AGENT=claude ctx "$R" entry --model m >/dev/null 2>&1
ctx "$R" end >/dev/null
out=$(soft '{"session_id":"s4","stop_hook_active":false}')
contains "soft: after ctx end, incomplete draft blocks" "$out" "ctx end was declared"
contains "soft: block exits 2" "$out" "rc=2"
fill_draft "$R" claude >/dev/null
equals "soft: finished entry → ok" "$(soft '{"session_id":"s4","stop_hook_active":false}')" "rc=0"

# --range (CI)
echo z >> "$R/README.md"; git -C "$R" commit -q -am "typo [no-ctx]"
git -C "$R" add new.py; git -C "$R" commit -q --no-verify -m "sneaky"
base=$(git -C "$R" rev-list --max-parents=0 HEAD)
out=$(ctx "$R" check --range "$base..HEAD")
contains "range: lists commit without journal" "$out" "sneaky"
contains "range: counts bypass" "$out" "1 bypass(es)"
check "range: report-only exit 0" ctx "$R" check --range "$base..HEAD"
check_fails "range --strict fails" ctx "$R" check --range "$base..HEAD" --strict

# status
out=$(ctx "$R" status)
contains "status: bypass rate" "$out" "Bypass rate:"
contains "status: brief size" "$out" "Brief:"
contains "status: missing commit listed" "$out" "sneaky"

finish
