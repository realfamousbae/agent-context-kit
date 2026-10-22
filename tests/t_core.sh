# Phase 2: ids, config, entry, claim, ask, compact on a single repo.
. "$(dirname "$0")/lib.sh"
R="$T_TMP/r"; mkrepo "$R"; kit_copy "$R"
today=$(date +%Y%m%d)

# --- ids
equals "first task id" "$(ctx "$R" id T)" "T-$today-aa-1"
printf -- '- G-%s-aa-7 · x\n' "$today" >> "$R/.context/GOTCHAS.md"
equals "id after existing G-…-7" "$(ctx "$R" id G)" "G-$today-aa-8"
equals "other authors' numbers do not count" "$(git -C "$R" config ctx.initials bb; ctx "$R" id G)" "G-$today-bb-1"
git -C "$R" config ctx.initials aa

# --- config
check "config set number" ctx "$R" config claim_stale_days 5
equals "config get" "$(ctx "$R" config claim_stale_days)" "5"
check "config adds a new key" ctx "$R" config my_key hello
equals "new key readable" "$(ctx "$R" config my_key)" "hello"
check_fails "config rejects unknown language" ctx "$R" config language xx
check_fails "config rejects bad push_claims" ctx "$R" config push_claims maybe
check "kit.json stays valid JSON" json_ok "$R/.context/kit.json"
ctx "$R" config claim_stale_days 3 >/dev/null

# --- entry
d1=$(ctx "$R" entry --agent claude --model test-model 2>/dev/null)
case $d1 in .context/journal/*-alice-claude.md) ok "draft name $d1" ;; *) not_ok "draft name" "$d1" ;; esac
fm=$(cat "$R/$d1")
contains "frontmatter model" "$fm" "model: test-model"
contains "frontmatter status draft" "$fm" "status: draft"
contains "frontmatter agent" "$fm" "agent: claude"
d2=$(ctx "$R" entry --agent claude --model test-model 2>/dev/null)
equals "second call returns the same draft" "$d2" "$d1"
check_fails "finish refuses empty required sections" ctx "$R" entry --finish --agent claude
fill_draft "$R" claude >/dev/null
fin=$(cat "$R/$d1")
contains "finished: status done" "$fin" "status: done"
not_contains "finished: empty optional sections dropped" "$fin" "ctx:for-humans"
not_contains "finished: template comments dropped" "$fin" "<!--  1–5"
contains "finished: required section kept" "$fin" "- did a thing"

# --- claim
ctx "$R" config push_claims never >/dev/null
commit_all "$R" "setup"
out=$(ctx "$R" claim --new "Upload files" --area "src/upload/ tests/test_upload*" 2>&1)
contains "claim --new creates a task" "$out" "Claimed T-$today-aa-1"
tasks=$(cat "$R/.context/TASKS.md")
contains "task in Now with owner/area" "$tasks" "- [ ] T-$today-aa-1 Upload files — @alice/human — since $(date +%Y-%m-%d) — area: \`src/upload/\`, \`tests/test_upload*\`"
equals "claim was committed" "$(git -C "$R" log -1 --format=%s)" "ctx: claim T-$today-aa-1"
# someone else claims an overlapping area
git -C "$R" config ctx.author bob; git -C "$R" config ctx.initials bb
check_fails "overlap with a fresh claim is refused" ctx "$R" claim --new "Refactor" --area "src/upload/client.py"
check_fails "glob overlap is refused" ctx "$R" claim --new "Tests" --area "tests/test_upload_big.py"
check "disjoint area is fine" ctx "$R" claim --new "Docs" --area "docs/"
check_fails "taking someone else's task is refused" ctx "$R" claim "T-$today-aa-1" --area "src/upload/"
check "--force after agreement" ctx "$R" claim --new "Hotfix" --area "src/upload/x.py" --force
# stale claim
git -C "$R" config ctx.author alice; git -C "$R" config ctx.initials aa
# dave has no journal activity, so his old claim is stale (alice's would not be: she wrote an entry today)
sed -e "s/@alice\/human — since $(date +%Y-%m-%d)/@dave\/human — since 2020-01-01/" "$R/.context/TASKS.md" > "$R/t" && mv "$R/t" "$R/.context/TASKS.md"
git -C "$R" config ctx.author carol; git -C "$R" config ctx.initials cc
out=$(ctx "$R" claim --new "Carol" --area "src/upload/a.py" 2>&1)
contains "stale claim is named stale" "$out" "(stale)"
git -C "$R" config ctx.author alice; git -C "$R" config ctx.initials aa
contains "brief marks it stale" "$(ctx "$R" brief)" "[STALE"
check "done releases the claim" ctx "$R" claim --done "T-$today-aa-1"
contains "task moved to Done" "$(sed -n '/ctx:done/,$p' "$R/.context/TASKS.md")" "- [x] T-$today-aa-1 Upload files"
not_contains "task gone from Now" "$(sed -n '/ctx:now/,/ctx:next/p' "$R/.context/TASKS.md")" "T-$today-aa-1"

# --- ask
out=$(ctx "$R" ask @bob "Can I change the checks format?" --task "T-$today-bb-1")
contains "question created" "$out" "Q-$today-aa-1 → @bob"
q=$(cat "$R/.context/QUESTIONS.md")
contains "question line" "$q" "- Q-$today-aa-1 · @bob · from alice/human · Can I change the checks format? (T-$today-bb-1)"
git -C "$R" config ctx.author bob; git -C "$R" config ctx.initials bb
contains "bob sees it as his" "$(ctx "$R" ask --list)" "Open, addressed to you:"
ctx "$R" ask --answer "Q-$today-aa-1" "yes, keep the actual key" >/dev/null
contains "answer appended with ✅" "$(cat "$R/.context/QUESTIONS.md")" "  - answer $(date +%Y-%m-%d) · bob/human: yes, keep the actual key ✅"
equals "no open questions after answer" "$(ctx "$R" ask --list)" "No open questions."
qa=$(sed -n '/ctx:open/,/ctx:archive/p' "$R/.context/QUESTIONS.md" | grep -c '^- Q-')
equals "question stays in the Open section until compaction" "$qa" "1"

# --- compact
git -C "$R" config ctx.author alice; git -C "$R" config ctx.initials aa
ctx "$R" config compact_keep_entries 1 >/dev/null
d3=$(ctx "$R" entry --agent codex --new 2>/dev/null)
sleep 1
fill_draft "$R" codex >/dev/null
contains "compact lists old entries" "$(ctx "$R" compact)" "$d1"
ctx "$R" compact --apply >/dev/null
check "old entry moved to archive" test -f "$R/.context/journal/archive/$(basename "$d1")"
check "newest entry kept" test -f "$R/$d3"
contains "answered question archived" "$(sed -n '/ctx:archive/,$p' "$R/.context/QUESTIONS.md")" "Q-$today-aa-1"

finish
