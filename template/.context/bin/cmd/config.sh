#!/bin/sh
# shellcheck source=../ctx-lib.sh
CTX_BIN=${CTX_BIN:-$(cd "$(dirname "$0")/.." && pwd)}
. "$CTX_BIN/ctx-lib.sh"
# ctx config [KEY [VALUE]] — read or change .context/kit.json (kept flat: one key per line).
ctx_init

[ $# -eq 0 ] && { cat "$CTX_JSON"; exit 0; }
key=$1
if [ $# -eq 1 ]; then
	v=$(ctx_cfg "$key" "")
	[ -n "$v" ] || ctx_die "no key '$key' in kit.json"
	printf '%s\n' "$v"
	exit 0
fi
value=$2
case $key in
	language)
		[ -f "$CTX_DIR/templates/$value/templates/entry.md" ] ||
			ctx_die "no templates for language '$value' in .context/templates/ (available: $(ls "$CTX_DIR/templates" | tr '\n' ' '))"
		raw="\"$value\"" ;;
	push_claims)
		case $value in ask|auto|never) raw="\"$value\"" ;; *) ctx_die "push_claims: ask | auto | never" ;; esac ;;
	strip_ai_coauthor|check_updates)
		case $value in true|false) raw=$value ;; *) ctx_die "$key: true | false" ;; esac ;;
	kit_version) ctx_die "kit_version is managed by install.sh --update" ;;
	*)
		case $value in
			''|*[!0-9]*)
				case $value in *'"'*|*'\'*) ctx_die "value must not contain quotes or backslashes" ;; esac
				raw="\"$value\"" ;;
			*) raw=$value ;;
		esac ;;
esac
ctx_cfg_set "$key" "$raw" || ctx_die "could not write $CTX_JSON"
ctx_say "kit.json: $key = $value"
[ "$key" = language ] && ctx_say "Existing records are not translated. New records use .context/templates/$value/."
exit 0
