# CLAUDE.md
@AGENTS.md

## Commands
- Build & install: `./build.sh` — compiles `main.swift`, creates
  `build/EnterRemap.app` (LSUIElement), installs to `/Applications`.
- Notarized release build: `./build.sh --notarize` with
  `NOTARY_KEY_PATH` / `NOTARY_KEY_ID` / `NOTARY_ISSUER_ID` env vars
  (App Store Connect API key method). Zip for distribution is created
  after stapling.
- No automated tests; verification is a successful build plus manual
  checks in target apps (Enter / Cmd+Enter / Shift+Enter / IME confirm
  Enter, with both Apple and Google Japanese Input).

## Project Conventions

- All in-app UI text (menu items, dialogs, status/log strings) is
  English. Japanese appears only in `README-ja.md`.
- The "do not modify README unless explicitly requested" rule in
  AGENTS.md applies to both `README.md` and `README-ja.md`.
- Install target: `/Applications` (admin account; no sudo required).
- TCC caveat: accessibility permission is tied to the code-signing
  identity. After a signature change (ad-hoc <-> Developer ID), the
  permission must be re-granted manually (remove & re-add in System
  Settings). Claude does not modify security settings; report and ask
  the project owner instead.
- Direct terminal execution of the binary makes the terminal the TCC
  responsible process; use `open /Applications/EnterRemap.app` for
  normal launch checks.

## Plan Mode
- Use plan mode for multi-file changes or unfamiliar code paths.
- Skip it for single-line/obvious fixes.

## Compact Instructions

When compacting, preserve working state for continuation, not chat history.

Always keep:
- Current goal and acceptance criteria
- Exact files changed, created, deleted, or inspected — and why
- Important functions, classes, routes, settings, commands, config keys
- Architectural / business rule decisions
- Rejected approaches and why they were rejected
- Errors, failed tests, commands run, and fixes attempted
- Pending tasks and the exact next step

Summarize:
- Completed exploration
- Older discussion
- Repeated command output

Drop:
- Verbose logs unless they contain unresolved errors
- Duplicate explanations
- Abandoned ideas no longer relevant

After compaction, re-read TASK.md (or the active task file in docs/tasks/) before continuing.
