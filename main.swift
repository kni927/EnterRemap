import Cocoa
import Carbon
import CoreGraphics
import Darwin
import UserNotifications

// Core idea (CGEventTap + eventSourceStateID for IME-safe Enter remap)
// credited to: https://qiita.com/nate3870/items/51b196de9a07717d3952

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
let KEYCODE_BACKSPACE: CGKeyCode = 51
let KEYCODE_ESCAPE: CGKeyCode = 53

// MARK: - IME composition detection
// Layered check; see docs/2026-07-12-01-ime-detection-notes.md for the
// investigation, tradeoffs, and known limitations.

// (1) Synthetic-event check kept from Phase 1: Apple JIS IME posts its
// confirm-Enter with a non-default source state ID.
func isSyntheticIMEEvent(_ event: CGEvent) -> Bool {
    return event.getIntegerValueField(.eventSourceStateID) != 1
}

// (2) Fast gate: composition is impossible unless the current input
// source is an IME in a non-Roman input mode (~0.01ms warm).
func isCJKInputModeActive() -> Bool {
    guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
          let prop = TISGetInputSourceProperty(src, kTISPropertyInputModeID) else {
        return false // plain keyboard layout (ABC etc.) has no input mode
    }
    let mode = Unmanaged<CFString>.fromOpaque(prop).takeUnretainedValue() as String
    return !mode.contains("Roman")
}

// (3) Composing state machine (Phase 3): tracks whether a conversion
// session is in progress from the keyDown history. Covers the window
//-detection blind spot in Google Japanese Input right after the first
// Space (suggestion window closed, candidate window not yet shown).
var composingKeyCount = 0
var lastFrontBundleID: String? = nil

// A key that feeds characters into the IME buffer: it produces a
// printable, non-space character at keyboard-layout level.
func generatesText(_ event: CGEvent) -> Bool {
    var length = 0
    var chars = [UniChar](repeating: 0, count: 4)
    event.keyboardGetUnicodeString(
        maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
    guard length > 0 else { return false }
    let c = chars[0]
    if c <= 0x20 || c == 0x7F { return false }            // controls, space
    if (0xF700...0xF8FF).contains(c) { return false }      // arrows, F-keys
    return true
}

func focusedUIElement() -> AXUIElement? {
    var focused: CFTypeRef?
    let systemWide = AXUIElementCreateSystemWide()
    guard AXUIElementCopyAttributeValue(
        systemWide, kAXFocusedUIElementAttribute as CFString, &focused
    ) == .success, let element = focused else { return nil }
    return (element as! AXUIElement)
}

// (4) Marked-text query. Chromium/Electron does not expose composition
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

// (5) Reinforcing signal: while composing, Google Japanese Input keeps a
// suggestion/candidate window on screen, owned by its Renderer process.
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

// MARK: - Notifications
// Symptomatic fix in place of launchd KeepAlive (rejected: it would also
// resurrect the process after a deliberate `killall`). Goal is only to
// notice that EnterRemap stopped running, not to diagnose why.

let notificationCenter = UNUserNotificationCenter.current()

func requestNotificationPermission() {
    // Idempotent: after the first grant/denial, the system answers
    // immediately without prompting again, so this can run every launch.
    notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, error in
        if let error = error {
            fputs("Notification authorization request failed: \(error)\n", stderr)
        }
    }
}

func notify(_ title: String, _ body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    notificationCenter.add(request) { error in
        if let error = error {
            fputs("Failed to post notification: \(error)\n", stderr)
        }
    }
}

// Keep sources alive; DispatchSourceSignal is cancelled if deallocated.
var terminationSignalSources: [DispatchSourceSignal] = []

func installTerminationNotifications() {
    for sig in [SIGTERM, SIGINT, SIGHUP] {
        signal(sig, SIG_IGN) // suppress default disposition so the source fires
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler {
            notify("EnterRemap", "終了しました。ログイン項目に登録していれば次回ログイン時に再起動されます。")
            // Pump the run loop briefly so the async notification request
            // (delivered via XPC on the main queue) has a chance to go out
            // before the process exits; this handler runs on the main
            // queue itself, so blocking it with a semaphore would deadlock.
            CFRunLoopRunInMode(.defaultMode, 2.0, false)
            exit(0)
        }
        source.resume()
        terminationSignalSources.append(source)
    }
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
            if !CGEvent.tapIsEnabled(tap: tap) {
                notify("EnterRemap", "イベントタップが無効化され、再有効化に失敗しました。アプリを再起動してください。")
            }
        }
        return Unmanaged.passRetained(event)
    }

    // A click commits any composition in progress (and moves focus).
    if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
        composingKeyCount = 0
        return Unmanaged.passRetained(event)
    }

    guard type == .keyDown else { return Unmanaged.passRetained(event) }

    // App switch ends the composing session (~1µs warm per event).
    let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    if bundleID != lastFrontBundleID {
        lastFrontBundleID = bundleID
        composingKeyCount = 0
    }
    let isTarget = bundleID.map(ALLOWED_BUNDLE_IDS.contains) ?? false
    guard isTarget else { return Unmanaged.passRetained(event) }

    let keycode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    let flags   = event.flags
    let isCmd   = flags.contains(.maskCommand)
    let isShift = flags.contains(.maskShift)

    // --- Remap path: Enter / Cmd+Enter ---
    if keycode == KEYCODE_ENTER {
        if isShift && !isCmd { return Unmanaged.passRetained(event) }
        if isSyntheticIMEEvent(event) {
            // Apple IME confirm-Enter: the session ends with it.
            composingKeyCount = 0
            return Unmanaged.passRetained(event)
        }
        if !isCJKInputModeActive() {
            composingKeyCount = 0 // mode switched away mid-session: committed
        } else {
            if composingKeyCount > 0 {
                // Conversion session in progress: let Enter confirm it.
                composingKeyCount = 0
                return Unmanaged.passRetained(event)
            }
            // Reinforcing signals (state machine may have missed the start).
            if axMarkedTextState() == true || isIMEUIWindowVisible() {
                return Unmanaged.passRetained(event)
            }
        }
        if isCmd {
            // Cmd+Enter -> plain Enter (send)
            event.flags = flags.subtracting(.maskCommand)
        } else {
            // Enter -> Shift+Enter (newline)
            event.flags = flags.union(.maskShift)
        }
        return Unmanaged.passRetained(event)
    }

    // --- Observation path: track composing state, never modify events ---
    if isSyntheticIMEEvent(event) { return Unmanaged.passRetained(event) }
    if keycode == KEYCODE_ESCAPE {
        composingKeyCount = 0 // conversion cancelled
    } else if isCmd {
        composingKeyCount = 0 // Cmd shortcut commits/aborts composition
    } else if keycode == KEYCODE_BACKSPACE {
        if composingKeyCount > 0 { composingKeyCount -= 1 }
    } else if !flags.contains(.maskControl),
              generatesText(event), isCJKInputModeActive() {
        composingKeyCount += 1
    }
    return Unmanaged.passRetained(event)
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

// Manual check for the notification path: `EnterRemap --test-notification`
// requests permission (if not yet determined) and fires one notification.
if CommandLine.arguments.contains("--test-notification") {
    requestNotificationPermission()
    notify("EnterRemap", "テスト通知です。これが表示されれば通知は正常に機能しています。")
    // No run loop is active yet at this point in main.swift's top-level
    // execution; pump one so the async authorization/notification XPC
    // round-trip can complete before the process exits.
    CFRunLoopRunInMode(.defaultMode, 5.0, false)
    exit(0)
}

requestNotificationPermission()
installTerminationNotifications()

let eventMask: CGEventMask =
    (1 << CGEventType.keyDown.rawValue) |
    (1 << CGEventType.leftMouseDown.rawValue) |
    (1 << CGEventType.rightMouseDown.rawValue) |
    (1 << CGEventType.otherMouseDown.rawValue)

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

// Pre-warm both paths: first calls pay one-time framework init
// (frontmostApplication ~10ms, composition check ~150ms, measured).
lastFrontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
_ = isCJKInputModeActive()
_ = focusedUIElement()
_ = isIMEUIWindowVisible()

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
CFRunLoopRun()
