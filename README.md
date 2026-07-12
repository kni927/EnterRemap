# EnterRemap

English | [日本語](README-ja.md)

A macOS menu-bar-less background tool that remaps Enter / Cmd+Enter in an
IME-safe way, so native AI chat apps don't send your message while you're
still converting Japanese (or other IME) input.

- **Enter** → newline (converted to Shift+Enter)
- **Cmd+Enter** → send (Cmd stripped, plain Enter)
- **Shift+Enter** → unchanged (newline)
- **Enter while composing with an IME** → unchanged (lets the IME confirm)

## Target apps

Frontmost app is checked against a bundle ID allowlist.

| App | Bundle ID |
|---|---|
| Claude | `com.anthropic.claudefordesktop` |
| ChatGPT (unified, post-Codex) | `com.openai.codex` |
| ChatGPT Classic | `com.openai.chat` |
| Gemini | `com.google.GeminiMacOS` |

Add an app by adding one line to `ALLOWED_BUNDLE_IDS` in [main.swift](main.swift).

Browser-based web apps are out of scope — covered separately by browser
extensions (e.g. "Chat AI Ctrl+Enter Sender").

## How IME detection works (v1.2)

While a target app is frontmost, EnterRemap observes keyDown events to
track whether an IME conversion session is in progress, then applies a
layered check on Enter (details:
[docs/2026-07-12-01-ime-detection-notes.md](docs/2026-07-12-01-ime-detection-notes.md)):

1. `eventSourceStateID != 1` → IME-synthetic event (Apple Japanese IME's
   confirm-Enter)
2. Current input source is Roman/non-IME → not composing (TIS query, ~0.01ms)
3. Composing-state tracking: a session starts on a text-generating
   keystroke while a Japanese input mode is active, and ends on
   Enter-confirm / Escape / mouse click / app switch / a Cmd shortcut —
   this also covers Google Japanese Input's blind spot right after the
   first Space conversion, when its candidate window isn't shown yet
4. Reinforcing signals: the focused element's `AXHasMarkedText`, and an
   on-screen window owned by the IME process (~4ms)

The observation path costs ~0.03ms per keyDown; the worst-case path on
Enter stays under 10ms — no perceptible latency.

## Build & install

```bash
./build.sh
```

This builds `build/EnterRemap.app` and installs it to `/Applications/EnterRemap.app`.

First-time setup:

1. **System Settings > Privacy & Security > Accessibility**: add EnterRemap
2. **System Settings > General > Login Items**: add EnterRemap
3. Launch: `open /Applications/EnterRemap.app`

Note: the app is ad-hoc signed, so a rebuild may require re-granting
Accessibility permission (remove and re-add the entry).

## Known Issues

- **Mouse click on the IME candidate window**: while a conversion
  candidate list is showing, clicking the composed text above it
  deselects and restores normal behavior, but clicking a candidate
  itself leaves the selection state in place. Typing afterward still
  works fine, so the practical impact is minimal, and confirming a
  conversion by mouse click is rare in practice — accepted as a known
  limitation.

## Credit

The core idea of an IME-safe Enter remap using CGEventTap +
`eventSourceStateID` comes from this article:
https://qiita.com/nate3870/items/51b196de9a07717d3952

## Workflow

This project follows a Chat-then-Code workflow:

1. Architecture/design decisions are made in chat and written into `TASK.md`.
2. Claude Code implements against `TASK.md`, committing per task.
3. Completed task phases are archived under `docs/tasks/`.

See `CLAUDE.md` for details.
