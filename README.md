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

## Crash/exit notifications (v1.3)

Auto-restart via launchd + KeepAlive was rejected: it would also resurrect
the process after a deliberate `killall`. Instead, EnterRemap posts a macOS
notification (via UserNotifications) so you notice it stopped:

- when the event tap is disabled and the existing auto-re-enable logic
  fails to recover it
- when SIGTERM/SIGINT/SIGHUP is caught (no attempt is made to distinguish
  this from an intentional `killall` — the goal is only to notice that it
  stopped, not to diagnose why)

This requires notification permission, requested automatically on first
launch. If you never see a notification, check **System Settings >
Notifications > EnterRemap**. `EnterRemap --test-notification` fires one
test notification for diagnostics.

**Known limitation**: delivery of these notifications could not be
verified end-to-end in the development environment, where macOS refused
the notification-permission request outright for an unnotarized app. See
[known-issues.md](known-issues.md) for details.

## Skipping single-line text fields (v1.3.1)

A single-line field like a Save As dialog's filename box renders as a
sheet/panel owned by the calling app (e.g. Claude Desktop), so the
frontmost-bundle-ID check alone can't tell it apart from the chat input —
Enter was getting remapped there too. In a single-line field, Enter means
"activate the default button", not "insert a newline", so the focused
element's AXRole now gates the remap:

- `AXTextField` (single-line) → pass through unchanged (Cmd+Enter too)
- `AXTextArea` or role unavailable (e.g. Electron) → existing remap + IME
  logic applies as before

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

## Status & stopping

```bash
pgrep -l EnterRemap   # check it's running
killall EnterRemap    # stop (no auto-restart; if registered as a Login
                      # Item, it comes back on next login)
open /Applications/EnterRemap.app   # restart
```

## Differences from the reference implementation

The [article this project is based on](https://qiita.com/nate3870/items/51b196de9a07717d3952)
targeted Claude only, and assumed Apple's standard Japanese IME
(live-conversion confirm) — it wasn't built with Google Japanese Input in
mind. This project extends that idea in a few ways (i.e. why a "similar"
tool exists rather than reusing the article's code as-is):

- Multiple target apps via a bundle ID allowlist (Claude / ChatGPT / Gemini)
- Correct behavior with Google Japanese Input: replaced the single
  `eventSourceStateID` heuristic with a layered check (TIS gate, AX/window
  detection, composing-state tracking — Phases 2-3, details in
  [docs/2026-07-12-01-ime-detection-notes.md](docs/2026-07-12-01-ime-detection-notes.md))
- Crash/exit notifications via UserNotifications, so an unintended stop
  doesn't go unnoticed (Phase 4)

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
