# Phase 3: real git hooks — journal rule, [no-ctx], CTX_SKIP, second session, secrets, co-author, chaining.
. "$(dirname "$0")/lib.sh"
R="$T_TMP/r"; mkrepo "$R"; kit_copy "$R"; enable_hooks "$R"
cp "$KIT_DIR/snippets/gitattributes" "$R/.gitattributes"
ctx "$R" config push_claims never >/dev/null
git -C "$R" add -A
check_fails "setup commit without entry is rejected" git -C "$R" commit -q -m "install kit"
check "setup commit with [no-ctx] passes" git -C "$R" commit -q -m "install kit [no-ctx]"

# code without entry
echo a > "$R/app.py"; git -C "$R" add app.py
out=$(git -C "$R" commit -m "add app" 2>&1); rc=$?
[ $rc -ne 0 ] && ok "code without journal entry rejected" || not_ok "code without journal entry rejected" "$out"
contains "message explains what to do" "$out" "ctx entry --agent"
contains "message mentions [no-ctx]" "$out" "[no-ctx]"

# draft does not count
(CTX_AGENT=claude ctx "$R" entry --model m >/dev/null 2>&1)
d=$(ctx "$R" entry --path --agent claude); git -C "$R" add "$d"
out=$(git -C "$R" commit -m "add app" 2>&1)
contains "draft entry rejected" "$out" "still a draft"

# finished entry passes, AI co-author stripped
fill_draft "$R" claude >/dev/null; git -C "$R" add "$d"
check "code + finished entry accepted" git -C "$R" commit -q -m "add app

Co-Authored-By: Claude <noreply@anthropic.com>"
not_contains "AI co-author line removed by commit-msg" "$(git -C "$R" log -1 --format=%B)" "Co-Authored-By"

# same session, second commit updates the same entry
echo b >> "$R/app.py"; printf -- '- also b\n' >> "$R/$d"
git -C "$R" add app.py "$d"
check "second commit of the session updates the same entry" git -C "$R" commit -q -m "more app"

# second session of the same day without a new entry is rejected
echo c >> "$R/app.py"; git -C "$R" add app.py
check_fails "second session without a new entry rejected" git -C "$R" commit -q -m "next session"
check "[no-ctx] bypass" git -C "$R" commit -q -m "typo [no-ctx]"
echo d >> "$R/app.py"; git -C "$R" add app.py
check "CTX_SKIP=1 bypass" env CTX_SKIP=1 git -C "$R" commit -q -m "emergency"
contains "CTX_SKIP leaves a trailer" "$(git -C "$R" log -1 --format=%B)" "Ctx-Skip: CTX_SKIP"
not_contains "commits before the kit are not counted" "$(ctx "$R" status)" "initial"
contains "status counts both bypasses" "$(ctx "$R" status)" "[no-ctx] 2, CTX_SKIP 1"

# secrets
printf -- '- token = abcdef123456\n' >> "$R/.context/MAP.md"; git -C "$R" add .context/MAP.md
out=$(git -C "$R" commit -m "map" 2>&1); rc=$?
[ $rc -ne 0 ] && ok "secret in .context rejected by pre-commit" || not_ok "secret rejected" "$out"
git -C "$R" reset -q; git -C "$R" checkout -q -- .context/MAP.md

# ctx claim commits go through the hooks (context only)
check "ctx claim commit passes the hooks" ctx "$R" claim --new "Task" --area "src/"
equals "claim commit exists" "$(git -C "$R" log -1 --format=%s)" "ctx: claim T-$(date +%Y%m%d)-aa-1"

# merge commit with code from the other branch is not rejected
git -C "$R" checkout -q -b side
echo s > "$R/side.py"; git -C "$R" add side.py; git -C "$R" commit -q -m "side [no-ctx]"
git -C "$R" checkout -q main
echo m > "$R/main.py"; git -C "$R" add main.py; git -C "$R" commit -q -m "main [no-ctx]"
check "merge commit accepted" git -C "$R" merge -q --no-edit side

# chaining a previous hook directory
mkdir -p "$R/.oldhooks"
printf '#!/bin/sh\necho chained >> "%s/chain.log"\n' "$T_TMP" > "$R/.oldhooks/pre-commit"
git -C "$R" config ctx.chainHooks .oldhooks
echo e >> "$R/app.py"; git -C "$R" add app.py; git -C "$R" commit -q -m "chain [no-ctx]"
contains "previous pre-commit hook still runs" "$(cat "$T_TMP/chain.log" 2>/dev/null)" "chained"
printf '#!/bin/sh\nexit 1\n' > "$R/.oldhooks/pre-commit"
echo f >> "$R/app.py"; git -C "$R" add app.py
check_fails "failing previous hook still blocks" git -C "$R" commit -q -m "chain2 [no-ctx]"

finish
