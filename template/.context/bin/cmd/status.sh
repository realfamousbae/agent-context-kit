#!/bin/sh
# shellcheck source=../ctx-lib.sh
CTX_BIN=${CTX_BIN:-$(cd "$(dirname "$0")/.." && pwd)}
. "$CTX_BIN/ctx-lib.sh"
# ctx status [--days N] — how well the protocol is followed.
ctx_init
days=$(ctx_cfg_int status_days 14)
[ "${1:-}" = --days ] && days=${2:-$days}
case $days in ''|*[!0-9]*) ctx_die "--days needs a number" ;; esac

ctx_say "ctx status — last $days days ($(ctx_author)/$(ctx_agent), language $(ctx_lang), kit $(ctx_cfg kit_version "?"))"
report=$(ctx_commit_classes --since="$days days ago" HEAD)
printf '%s\n' "$report" | awk -F '\t' '
	NF { n[$2]++; if ($2 != "context") code++ }
	END {
		by = n["noctx"] + n["skip"] + n["missing"]
		printf "Commits with code: %d — with journal %d, [no-ctx] %d, CTX_SKIP %d, without journal (hooks bypassed) %d\n",
			code, n["journal"], n["noctx"], n["skip"], n["missing"]
		printf "Bypass rate: %s (target: at most 10%%)\n", code ? sprintf("%d%%", by * 100 / code) : "n/a"
		printf "Context-only commits: %d\n", n["context"]
	}'
missing=$(printf '%s\n' "$report" | awk -F '\t' '$2 == "missing"' | head -n 10)
[ -n "$missing" ] && { ctx_say "Without journal:"; printf '%s\n' "$missing" | awk -F '\t' '{ printf "  %s %s %s — %s\n", $1, $4, $3, $5 }'; }

entries=$(ctx_entries | wc -l | tr -d ' ')
arch=$(find .context/journal/archive -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
size=$("${CTX_SHELL:-sh}" "$CTX_BIN/ctx" brief --no-fetch 2>/dev/null | wc -c | tr -d ' ')
ctx_say "Journal: $entries entries ($arch archived; compaction at $(ctx_cfg_int compact_threshold_entries 30))"
ctx_say "Brief: $size bytes (budget $(ctx_cfg_int brief_budget_bytes 24000))"

stale=$(ctx_tasks_in now | while IFS= read -r l; do
	case $l in (*" — paused "*) continue ;; esac
	[ -n "$(ctx_task_field "$l" owner)" ] && ctx_claim_is_stale "$l" && printf '  %s (%s days)\n' "$l" "$(ctx_claim_age_days "$l")"
done)
[ -n "$stale" ] && { ctx_say "Stale claims (older than $(ctx_cfg_int claim_stale_days 3) days without activity):"; printf '%s\n' "$stale"; }

qdays=$(ctx_cfg_int question_stale_days 3)
oldq=$(ctx_questions .context/QUESTIONS.md all "" | grep '^- Q-' | while IFS= read -r q; do
	d=$(printf '%s' "$q" | sed -n 's/^- Q-\([0-9]\{8\}\)-.*/\1/p')
	[ -n "$d" ] && [ "$(ctx_days_between "$d" "$(ctx_today_compact)")" -gt "$qdays" ] && printf '  %s\n' "$q"
done)
[ -n "$oldq" ] && { ctx_say "Open questions older than $qdays days:"; printf '%s\n' "$oldq" | cut -c1-200; }
drafts=$(for f in $(ctx_entries); do ctx_is_draft "$f" && printf '  %s\n' "$f"; done)
[ -n "$drafts" ] && { ctx_say "Drafts:"; printf '%s\n' "$drafts"; }
exit 0
