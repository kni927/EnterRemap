# EnterRemap

English | [日本語](README-ja.md)

A macOS background tool (no Dock icon, a menu bar status item only) that
remaps Enter / Cmd+Enter in an IME-safe way, so native AI chat apps don't
send your message while you're still converting Japanese (or other IME)
input.

- **Enter** → newline (converted to Shift+Enter)
- **Cmd+Enter** → send (Cmd stripped, plain Enter)
- **Shift+Enter** → unchanged (newline)
- **Enter while composing with an IME** → unchanged (lets the IME confirm)

## Target apps (v1.5)

Frontmost app is checked against a bundle ID allowlist. The allowlist
persists in `UserDefaults` and can be toggled at runtime — no rebuild —
from the menu bar's **Target Apps...** window:

| Preset | Bundle ID | Default |
|---|---|---|
| Claude | `com.anthropic.claudefordesktop` | ON |
| ChatGPT (unified, post-Codex) | `com.openai.codex` | ON |
| ChatGPT Classic | `com.openai.chat` | ON |
| Gemini | `com.google.GeminiMacOS` | ON |
| Discord | `com.hnc.Discord` | OFF |

Apps not in the preset list can be added from the same window's manual
bundle-ID field — checking it enables the remap immediately.

Browser-based web apps are out of scope — covered separately by browser
extensions (e.g. "Chat AI Ctrl+Enter Sender").

## Menu bar icon (v1.4)

A one-shot notification on crash (Phase 4) turned out easy to miss — by
the time it appeared, it had often already gone unnoticed. Replaced with
an always-visible menu bar status item instead:

- **Running** — small monochrome dot, follows light/dark mode
- **Paused** — small dot tinted `#E0B03E` (toggled from the menu; the
  process keeps running)
- **Tap Recovery Failed** — small dot tinted `#C9615C`; the event tap was
  disabled and the existing auto-re-enable logic failed to recover it
  (needs a restart)

Click the icon for a menu with the current state, "Target Apps...",
"Pause/Resume", and "Quit". While paused, Enter/Cmd+Enter pass through
completely untouched —
this skips the single-line-field check and all IME logic too for any
target-app keystroke, on the principle that doing nothing beats guessing
wrong while the user has explicitly asked the tool to stand down.

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

Normally the menu bar icon (a small dot: gray-scale/yellow/red) and its
"Pause/Resume"/"Quit" menu
items are all you need. From a terminal:

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
- An always-visible menu bar status icon, so an unintended stop doesn't
  go unnoticed (Phase 4 first tried UserNotifications for this, but a
  one-shot notification proved too easy to miss and was replaced in
  Phase 5)
- AXRole-gated remap so Enter behaves correctly in single-line fields
  like a Save As dialog's filename box (Phase 6)
- Target apps are editable at runtime (UserDefaults-backed allowlist,
  a "Target Apps..." window with checkboxes and a manual bundle-ID
  field) instead of a hardcoded list requiring a rebuild (Phase 7)

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
