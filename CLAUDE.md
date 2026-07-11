# CLAUDE.md

This file guides Claude Code when working in this repository.

## Workflow

- Architecture and design decisions happen in chat (claude.ai), not here.
- Implementation happens here, driven by `TASK.md` at the repo root.
- `TASK.md` is a fixed filename. When a phase is complete, archive it to
  `docs/tasks/` with a date-prefixed filename (e.g. `docs/tasks/2026-07-12-enter-remap-multiapp.md`)
  before starting the next phase.
- Prefer commit-per-task, with a build/test verification step before each commit.
- Direct branch merges are fine for solo-developer work; PRs are not required
  unless explicitly requested.

## Conventions

- Write code comments and commit messages in English for token efficiency.
- Follow semantic versioning for tagged releases.
- Keep a `dev-log.md` and `known-issues.md` if the project grows enough to
  warrant tracking either.

## Build & Test

- `./build.sh` — compiles `main.swift`, creates `build/EnterRemap.app`
  (LSUIElement, ad-hoc signed), and installs it to `~/Applications`.
- No automated tests; verification is a successful build plus manual checks
  in the target apps (Enter / Cmd+Enter / Shift+Enter / IME confirm Enter).
