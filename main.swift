import Cocoa
import Carbon
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

// MARK: - App gate

func isTargetAppActive() -> Bool {
    guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
        return false
    }
    return ALLOWED_BUNDLE_IDS.contains(bundleID)
}

// MARK: - IME composition detection
// Layered check, evaluated only for Enter/Cmd+Enter in target apps.
// See docs/2026-07-12-ime-detection-notes.md for the investigation
// behind this design and its known limitations.

// (1) Synthetic-event check kept from Phase 1: Apple JIS IME posts its
// confirm-Enter with a non-default source state ID. Removing this would
// regress Apple IME (live-conversion confirm shows no candidate window,
// so the window check below cannot catch it).
func isSyntheticIMEEvent(_ event: CGEvent) -> Bool {
    return event.getIntegerValueField(.eventSourceStateID) != 1
}

// (2) Fast gate: composition is impossible unless the current input
// source is an IME in a non-Roman input mode (~0.01ms).
func isCJKInputModeActive() -> Bool {
    guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
          let prop = TISGetInputSourceProperty(src, kTISPropertyInputModeID) else {
        return false // plain keyboard layout (ABC etc.) has no input mode
    }
    let mode = Unmanaged<CFString>.fromOpaque(prop).takeUnretainedValue() as String
    return !mode.contains("Roman")
}

func focusedUIElement() -> AXUIElement? {
    var focused: CFTypeRef?
    let systemWide = AXUIElementCreateSystemWide()
    guard AXUIElementCopyAttributeValue(
        systemWide, kAXFocusedUIElementAttribute as CFString, &focused
    ) == .success, let element = focused else { return nil }
    return (element as! AXUIElement)
}

// (3) Marked-text query. Chromium/Electron does not expose composition
// state through AX today, so this usually returns nil; trusted only when
// the element explicitly reports a boolean.
func axMarkedTextState() -> Bool? {
    guard let element = focusedUIElement() else { return nil }
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, "AXHasMarkedText" as CFString, &value) == .success,
       let hasMarked = value as? Bool {
        return hasMarked
    }
    return nil
}

// (4) Fallback: while composing, Google Japanese Input keeps a
// suggestion/candidate window on screen, owned by its Renderer process.
// Any on-screen window owned by a running IME process counts (~1.7ms).
func isIMEUIWindowVisible() -> Bool {
    var imePids = Set<pid_t>()
    for app in NSWorkspace.shared.runningApplications {
        if let bid = app.bundleIdentifier, bid.contains("inputmethod") {
            imePids.insert(app.processIdentifier)
        }
    }
    guard !imePids.isEmpty,
          let windows = CGWindowListCopyWindowInfo(
              [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
          ) as? [[String: Any]] else { return false }
    return windows.contains { window in
        guard let pid = window[kCGWindowOwnerPID as String] as? pid_t else { return false }
        return imePids.contains(pid)
    }
}

// Defaults to "not composing" (remap) when no signal fires: a false
// "composing" would let Enter through and send the message — the exact
// accident this tool exists to prevent.
func isComposing(_ event: CGEvent) -> Bool {
    if isSyntheticIMEEvent(event) { return true }
    if !isCJKInputModeActive() { return false }
    if let hasMarked = axMarkedTextState() { return hasMarked }
    return isIMEUIWindowVisible()
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
    if isShift && !isCmd { return Unmanaged.passRetained(event) }
    if isComposing(event) { return Unmanaged.passRetained(event) }

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

// MARK: - Probe mode (diagnostics)
// Run `EnterRemap --probe` from a terminal while composing text to dump
// every composition signal plus its latency. Used to verify AX attribute
// availability per app and to re-measure the latency budget.

func runProbe() {
    print("AXIsProcessTrusted: \(AXIsProcessTrusted())")
    for i in 1...10 {
        print("\n--- probe \(i)/10 ---")
        var t0 = DispatchTime.now()
        let cjk = isCJKInputModeActive()
        let tisMs = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6

        var srcID = "?", modeID = "nil"
        if let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
            if let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) {
                srcID = Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
            }
            if let p = TISGetInputSourceProperty(src, kTISPropertyInputModeID) {
                modeID = Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
            }
        }
        print("input source: \(srcID) mode=\(modeID) cjk=\(cjk) [\(String(format: "%.3f", tisMs))ms]")

        t0 = DispatchTime.now()
        let element = focusedUIElement()
        let axMs = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6
        if let element = element {
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            var names: CFArray?
            var attrs = "(unavailable)"
            if AXUIElementCopyAttributeNames(element, &names) == .success,
               let names = names as? [String] {
                attrs = names.joined(separator: ",")
            }
            print("focused element: pid=\(pid) [\(String(format: "%.3f", axMs))ms]")
            print("  attributes: \(attrs)")
            print("  AXHasMarkedText: \(String(describing: axMarkedTextState()))")
        } else {
            print("focused element: none [\(String(format: "%.3f", axMs))ms]")
        }

        t0 = DispatchTime.now()
        let imeWin = isIMEUIWindowVisible()
        let winMs = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6
        print("IME UI window visible: \(imeWin) [\(String(format: "%.3f", winMs))ms]")
        print("total worst-path: \(String(format: "%.3f", tisMs + axMs + winMs))ms")
        Thread.sleep(forTimeInterval: 1.0)
    }
}

// MARK: - Main

if CommandLine.arguments.contains("--probe") {
    runProbe()
    exit(0)
}

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

// Pre-warm the composition-check path: the first call pays one-time
// framework initialization (~150ms measured); warm calls are 1-9ms.
_ = isCJKInputModeActive()
_ = focusedUIElement()
_ = isIMEUIWindowVisible()

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
CFRunLoopRun()
