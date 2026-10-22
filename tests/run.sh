#!/bin/sh
# Run all kit tests: sh tests/run.sh [t_name ...]
# TEST_SH selects the shell used for the test scripts and for ctx itself (default: sh).
set -u
cd "$(dirname "$0")" || exit 1
TEST_SH=${TEST_SH:-sh}
failed=""
if [ $# -gt 0 ]; then list=$*; else list=$(ls t_*.sh); fi
for t in $list; do
	case $t in *.sh) ;; *) t="$t.sh" ;; esac
	echo "== $t ($TEST_SH)"
	if ! "$TEST_SH" "./$t"; then failed="$failed $t"; fi
done
if [ -n "$failed" ]; then
	echo "FAILED:$failed"
	exit 1
fi
echo "ALL PASSED"
