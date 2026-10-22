# Phase 2: two participants, two clones, one bare remote — claims, questions and entries travel via git.
. "$(dirname "$0")/lib.sh"
today=$(date +%Y%m%d)
B="$T_TMP/remote.git"; A="$T_TMP/alice"; C="$T_TMP/bob"
git init -q --bare "$B"
git -C "$B" symbolic-ref HEAD refs/heads/main
mkrepo "$A"; kit_copy "$A"
cp "$KIT_DIR/snippets/gitattributes" "$A/.gitattributes"
commit_all "$A" "install kit"
git -C "$A" remote add origin "$B"; git -C "$A" push -q -u origin main 2>/dev/null
git clone -q "$B" "$C"
git -C "$C" config ctx.author bob; git -C "$C" config ctx.initials bb

# alice claims and pushes automatically
ctx "$A" config push_claims auto >/dev/null; commit_all "$A" "auto push [no-ctx]"; git -C "$A" push -q 2>/dev/null
out=$(ctx "$A" claim --new "Upload" --area "src/upload/")
contains "auto push of the claim" "$out" "Pushed the claim"
git -C "$C" pull -q --rebase
contains "bob sees alice's claim after pull" "$(ctx "$C" brief)" "@alice/human — since"
check_fails "bob cannot claim an overlapping area" ctx "$C" claim --new "Refactor" --area "src/"

# bob asks with a personal override push_claims=ask — gets the command, then pushes himself
git -C "$C" config ctx.pushClaims ask
out=$(ctx "$C" ask @alice "May I touch src/upload/util.py?" --commit)
contains "ask mode prints the push command" "$out" "git push origin HEAD:main"
git -C "$C" push -q 2>/dev/null
git -C "$A" pull -q --rebase
contains "alice sees bob's question" "$(ctx "$A" brief)" "May I touch src/upload/util.py?"
ctx "$A" ask --answer "Q-$today-bb-1" "yes" --commit >/dev/null; git -C "$A" push -q 2>/dev/null
git -C "$C" pull -q --rebase
not_contains "answered question leaves bob's brief" "$(ctx "$C" brief)" "May I touch"

# bob works on a branch; alice sees his entry and claim before any merge
git -C "$C" checkout -q -b feature/export
ctx "$C" claim --new "Export" --area "src/export/" --no-push >/dev/null
CTX_AGENT=codex ctx "$C" entry --model m >/dev/null 2>&1; d=$(fill_draft "$C" codex)
mkdir -p "$C/src/export"; echo x > "$C/src/export/a.py"
commit_all "$C" "export"
git -C "$C" push -q -u origin feature/export 2>/dev/null
out=$(CTX_NO_FETCH=0 ctx "$A" brief)
contains "alice sees bob's branch entry" "$out" "[branch origin/feature/export]"
contains "alice sees bob's branch claim" "$out" "Export — @bob/human"
check_fails "alice cannot claim bob's branch area" ctx "$A" claim --new "Mine" --area "src/export/x.py" --no-push

finish
