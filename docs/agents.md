# Agent integration notes

What the kit relies on in Claude Code and Codex, checked against their documentation on 2026-10-22
(Claude Code 2.1.303, Codex CLI 0.163.0). If an agent changes, this is the list to re-check.

## Claude Code

Source: https://code.claude.com/docs/en/hooks, https://code.claude.com/docs/en/slash-commands

| Fact | How the kit uses it |
| --- | --- |
| `SessionStart` matchers: `startup`, `resume`, `clear`, `compact`, `fork`. Plain stdout of a SessionStart hook is added to Claude's context — and stays in the transcript, re-sent with every request | `ctx brief --hook`: the start card (`start_budget_bytes`, 2,500) on `startup\|clear`, only warnings and questions on `resume`; `--short` (goal, draft, claims) on `compact` |
| Hook output added to context is capped at **10,000 characters**; longer output is replaced by a file path and a 2,000-character preview | The card is far below the cap; `ctx brief --full` is for on-demand use |
| `PreToolUse` handlers take an `if` permission rule (`"Bash(git push*)"`, `*` anywhere); a non-matching command never spawns the hook. `permissionDecision`: `allow` skips the user's permission prompt, `ask` shows one with the reason, `deny` blocks. `additionalContext` arrives with the tool result, i.e. after the command ran | `ctx checkpoint --hook` on push/deploy/publish/apply/helm/release patterns, for `Bash` and `PowerShell`; prints nothing when the outcome is `met`, `ask` otherwise; never `allow` |
| `PreCompact` output is not added to the context (its `systemMessage` is discarded; exit 2 blocks compaction) | Not used. `SessionStart(compact)` brings the claim, questions and the draft back |
| `Stop` fires every time Claude finishes responding (per turn), not per session. Exit 2: stderr goes to Claude as the reason to continue. Input has `stop_hook_active` | Not used since 0.2: a per-turn hook is the opposite of "context at entry and exit". The journal is enforced at commits; `ctx check --soft` remains for projects that want it |
| Hook commands run with `sh -c` on macOS/Linux and in **Git Bash on Windows** (PowerShell only when Git Bash is missing) | Commands are `sh "${CLAUDE_PROJECT_DIR}/.context/bin/ctx" …`; `${CLAUDE_PROJECT_DIR}` is the form the docs recommend (also rewritten for PowerShell) |
| `CLAUDE_PROJECT_DIR` stays at the original project root in worktrees; the `cwd` input field follows the session | `--hook` reads `cwd` from the hook JSON and works there |
| Project hooks run only after the workspace trust dialog (interactive); `-p`/SDK sessions treat the folder as trusted | Nothing to do; mentioned in BOOTSTRAP |
| `.claude/commands/*.md` still works (the older form of skills) | `/ctx-start`, `/ctx-end`, `/ctx-compact`, `/ctx-ask` |

## Codex

Source: https://developers.openai.com/codex/llms-full.txt (hooks, AGENTS.md, sandboxing, Windows sections)

| Fact | How the kit uses it |
| --- | --- |
| Hooks are on by default; project hooks live in `<repo>/.codex/hooks.json` and load only when the project `.codex/` layer is trusted; each hook must be reviewed and trusted (`/hooks`), trust is tied to the hook's hash | Installer writes `.codex/hooks.json`; each person approves it once with `/hooks` (again after a kit update changes it) |
| `SessionStart` sources: `startup`, `resume`, `clear`, `compact`, `fork`. Plain stdout or `hookSpecificOutput.additionalContext` becomes developer context; default limit ~2,500 tokens, `additionalContextLimit` changes it | `ctx brief --hook --format codex` prints the JSON form; limits 1,500 tokens (card) / 3,000 (compact) |
| `PreToolUse` (matcher on `tool_name`, e.g. `Bash`; no `if` filter) can return `permissionDecision: "deny"` with a reason or `additionalContext`; `"ask"` is parsed but not supported yet; plain stdout is ignored | `ctx checkpoint --hook --format codex`: a plain-sh fast path exits silently for ordinary commands (it spawns on every Bash call); for push/deploy with an outcome other than `met` it denies with the card and tells the model to ask the user and rerun with `CTX_CONFIRMED=1` — a speed bump, not enforcement, since the model can add the prefix itself |
| `Stop` must print JSON on exit 0 | Not used since 0.2 |
| Commands run with the session `cwd`, which may be a subdirectory; `commandWindows` overrides the command on Windows | `$(git rev-parse --show-toplevel)` in `command`; `commandWindows` runs `ctx.ps1` through `powershell -NoProfile -ExecutionPolicy Bypass` |
| `AGENTS.md` files are concatenated root → cwd until `project_doc_max_bytes` (**32 KiB**) is reached; `AGENTS.override.md` replaces `AGENTS.md` in its directory | The ctx block is ~1.5 KB and goes first; the installer warns about `AGENTS.override.md` |
| `workspace-write` sandbox: network off by default; `.git`, `.codex`, `.agents` are read-only (recursively) | `ctx brief` warns instead of failing when fetch fails; `ctx claim`/`ctx ask --commit` print the git command for the user; the installer prints what to merge if `.codex/` is not writable |
| `read-only` sandbox: nothing is writable, not even temp directories | `ctx brief` uses no temporary files |
| On Windows the native agent runs commands in PowerShell | AGENTS.md gives `.context\bin\ctx.cmd brief`; `ctx.ps1` is the PowerShell wrapper |

## What is verified, and how

- Every hook command is run by `tests/t_agents.sh` exactly as installed, with hook JSON on stdin (startup, compact,
  worktree `cwd`, Stop with and without `stop_hook_active`), on Ubuntu, macOS and Windows (Git Bash with a
  `C:\…` project dir). Codex `commandWindows` runs through `cmd /c` + PowerShell in Windows CI.
- Live on macOS: `claude -p` in a fresh repository retold the other participant's entry, claim, gotcha and the
  question addressed to it from the SessionStart hook alone.
- Live on macOS, Codex 0.163.0, `codex exec -s read-only` in a **trusted** project: the SessionStart hook injected the
  brief (recorded in the session log as a developer message, `hooks.additional_context`), and Codex answered
  questions about the other participant's claim and gotcha without running any command.
- In an **untrusted** project Codex ignores `.codex/` entirely (documented), so the hook does not run; Codex then
  follows AGENTS.md and runs `ctx brief` itself — also verified live. Trust comes from the folder-trust prompt of the
  Codex TUI, or `[projects."<abs path>"] trust_level = "trusted"` in `~/.codex/config.toml`.
- Live, kit 0.2, synthetic two-person project (macOS): `claude -p` retold the start card (bob's work, the claim,
  the question for alice); asked to run `git push` with the session outcome `in-progress`, the PreToolUse hook
  stopped it with the checkpoint card (in `-p` an "ask" counts as denied) and nothing was pushed. `codex exec` in
  the trusted project: the same push was denied with the card and the `CTX_CONFIRMED=1` instruction.
- Not run live: a real `/compact` (only simulated with `source: compact`), Claude Code and Codex sessions on Windows.
