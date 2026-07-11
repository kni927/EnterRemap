import Cocoa
import CoreGraphics

// MARK: - Configuration

// Allowed target apps (bundle IDs). Single source of truth —
// add a new bundle ID here to support another app.
let ALLOWED_BUNDLE_IDS: Set<String> = [
    "com.anthropic.claudefordesktop", // Claude
    "com.openai.codex",               // ChatGPT (unified app, post-Codex merge)
    "com.openai.chat",                // ChatGPT Classic (legacy)
    "com.google.GeminiMacOS",         // Gemini
]

let KEYCODE_ENTER: CGKeyCode = 36

// MARK: - Guards

func isTargetAppActive() -> Bool {
    guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
        return false
    }
    return ALLOWED_BUNDLE_IDS.contains(bundleID)
}

// IME-generated events (e.g. conversion-confirm Enter) carry an
// eventSourceStateID other than 1; pass them through untouched.
func isIMEEvent(_ event: CGEvent) -> Bool {
    return event.getIntegerValueField(.eventSourceStateID) != 1
}

// MARK: - Event tap

var eventTap: CFMachPort?

func eventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // The system disables a tap whose callback stalls; re-enable and continue.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    guard type == .keyDown else { return Unmanaged.passRetained(event) }
    let keycode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    let flags   = event.flags
    let isCmd   = flags.contains(.maskCommand)
    let isShift = flags.contains(.maskShift)

    guard keycode == KEYCODE_ENTER else { return Unmanaged.passRetained(event) }
    guard isTargetAppActive() else { return Unmanaged.passRetained(event) }
    if isIMEEvent(event) { return Unmanaged.passRetained(event) }
    if isShift && !isCmd { return Unmanaged.passRetained(event) }

    if isCmd {
        // Cmd+Enter -> plain Enter (send)
        event.flags = flags.subtracting(.maskCommand)
        return Unmanaged.passRetained(event)
    } else {
        // Enter -> Shift+Enter (newline)
        event.flags = flags.union(.maskShift)
        return Unmanaged.passRetained(event)
    }
}

// MARK: - Main

let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: eventMask,
    callback: eventCallback,
    userInfo: nil
) else {
    fputs("Failed to create event tap. Grant Accessibility permission in "
        + "System Settings > Privacy & Security > Accessibility.\n", stderr)
    exit(1)
}
eventTap = tap

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
CFRunLoopRun()
