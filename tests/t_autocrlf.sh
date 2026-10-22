# Phase 2: core.autocrlf=true clones keep LF in scripts (thanks to .gitattributes) and ctx runs.
. "$(dirname "$0")/lib.sh"
A="$T_TMP/a"; mkrepo "$A"; kit_copy "$A"
cp "$KIT_DIR/snippets/gitattributes" "$A/.gitattributes"
commit_all "$A" "install kit"
git clone -q -c core.autocrlf=true "$A" "$T_TMP/win"
W="$T_TMP/win"
git -C "$W" config ctx.author bob; git -C "$W" config ctx.initials bb
# count CR bytes (not awk: MSYS gawk reads files in text mode and drops CRs)
cr() { tr -dc '\r' < "$1" | wc -c | tr -d ' '; }
equals "ctx has LF" "$(cr "$W/.context/bin/ctx")" "0"
equals "ctx-lib.sh has LF" "$(cr "$W/.context/bin/ctx-lib.sh")" "0"
equals "cmd/brief.sh has LF" "$(cr "$W/.context/bin/cmd/brief.sh")" "0"
equals "journal template has LF" "$(cr "$W/.context/templates/en/templates/entry.md")" "$(cr "$W/.context/templates/en/templates/entry.md")"
[ "$(cr "$W/.context/bin/ctx.cmd")" -gt 0 ] && ok "ctx.cmd has CRLF" || not_ok "ctx.cmd has CRLF"
out=$(ctx "$W" brief); rc=$?
equals "brief runs in an autocrlf clone" "$rc" "0"
contains "brief output" "$out" "you are bob/"
# records written with CRLF in the work tree still parse
printf -- '- G-20261022-bb-1 · crlf trap — fine\r\n' >> "$W/.context/GOTCHAS.md"
contains "CRLF gotcha line is read" "$(ctx "$W" brief)" "crlf trap"
check "claim works in an autocrlf clone" ctx "$W" claim --new "Win task" --area "src/" --no-push

# control: without the attributes the same clone would break the scripts
mkrepo "$T_TMP/b"; kit_copy "$T_TMP/b"; commit_all "$T_TMP/b" "no attributes"
git clone -q -c core.autocrlf=true "$T_TMP/b" "$T_TMP/bad"
[ "$(cr "$T_TMP/bad/.context/bin/ctx-lib.sh")" -gt 0 ] && ok "control: no attributes → CRLF scripts" || not_ok "control: no attributes → CRLF scripts"

finish
