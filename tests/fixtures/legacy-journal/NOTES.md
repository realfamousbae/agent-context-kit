# Notes

## Gotchas
- `make test` needs `TZ=UTC`, otherwise the date tests fail
- The demo API answers 200 with an error body on bad input

## In progress
- Export to CSV (codex, `src/export/`)

## Questions to each other
- @codex: can we drop the legacy `--fast` flag?
- @claude: is the cache still needed? ✅ answered: no

## Decisions
- Use SQLite for local storage

## Ideas
- Add a dark theme
