#!/bin/sh
# shellcheck source=../ctx-lib.sh
CTX_BIN=${CTX_BIN:-$(cd "$(dirname "$0")/.." && pwd)}
. "$CTX_BIN/ctx-lib.sh"
# ctx id T|D|G|Q — print the next free ID for this author today.
ctx_init
case ${1:-} in
	T|D|G|Q) ctx_next_id "$1" ;;
	t|d|g|q) ctx_next_id "$(printf '%s' "$1" | tr 'tdgq' 'TDGQ')" ;;
	*) ctx_die "usage: ctx id T|D|G|Q (task, decision, gotcha, question)" ;;
esac
