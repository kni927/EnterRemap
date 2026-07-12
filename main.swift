import Cocoa
import Carbon
import CoreGraphics

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

// (Phase 6) Role of the focused element. A single-line AXTextField (e.g.
// a Save As filename field, a search box) uses Enter to trigger the
// default button, not to insert a newline — the remap must not apply
// there. This also covers sheets/panels (e.g. Save As) that render as
// part of the owning app, so the frontmost-bundle-ID check alone cannot
// distinguish them from the chat input.
func focusedElementRole() -> String? {
    guard let element = focusedUIElement() else { return nil }
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success,
          let role = value as? String else { return nil }
    return role
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

// MARK: - Status bar
// Replaces Phase 4's UserNotifications-based alerts: a one-shot
// notification is easy to miss or forget about, so instead show current
// state persistently in the menu bar (also lets the user pause/resume
// and quit without a terminal).

var isPaused = false
var tapHealthy = true

let STATUS_DOT_DIAMETER: CGFloat = 8
let STATUS_PAUSED_COLOR = NSColor(red: 0xE0 / 255, green: 0xB0 / 255, blue: 0x3E / 255, alpha: 1)
let STATUS_FAILED_COLOR = NSColor(red: 0xC9 / 255, green: 0x61 / 255, blue: 0x5C / 255, alpha: 1)

// A small filled circle. `template: true` yields a monochrome image that
// AppKit auto-tints for the menu bar's current appearance (light/dark);
// used for the "running" state. Colored states render as-is untinted.
func dotImage(diameter: CGFloat, color: NSColor, template: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
        return true
    }
    image.isTemplate = template
    return image
}

func menuItemFont() -> NSFont {
    NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
}

func menuItemTitle(_ text: String) -> NSAttributedString {
    NSAttributedString(string: text, attributes: [
        .font: menuItemFont(),
        .foregroundColor: NSColor.labelColor,
    ])
}

final class StatusMenuController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "", action: #selector(togglePause), keyEquivalent: "")

    override init() {
        super.init()
        let menu = NSMenu()
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(NSMenuItem.separator())
        pauseItem.target = self
        menu.addItem(pauseItem)
        let quitItem = NSMenuItem(title: "終了", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.attributedTitle = menuItemTitle("終了")
        menu.addItem(quitItem)
        menu.addItem(NSMenuItem.separator())
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "EnterRemap v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        versionItem.attributedTitle = menuItemTitle("EnterRemap v\(version)")
        menu.addItem(versionItem)
        statusItem.menu = menu
        refresh()
    }

    func refresh() {
        let image: NSImage
        let stateText: String
        if !tapHealthy {
            image = dotImage(diameter: STATUS_DOT_DIAMETER, color: STATUS_FAILED_COLOR, template: false)
            stateText = "Tap Recovery Failed"
        } else if isPaused {
            image = dotImage(diameter: STATUS_DOT_DIAMETER, color: STATUS_PAUSED_COLOR, template: false)
            stateText = "Paused"
        } else {
            image = dotImage(diameter: STATUS_DOT_DIAMETER, color: NSColor.labelColor, template: true)
            stateText = "Running"
        }
        statusItem.button?.image = image
        statusItem.button?.title = ""
        stateItem.attributedTitle = menuItemTitle(stateText)
        pauseItem.attributedTitle = menuItemTitle(isPaused ? "再開" : "一時停止")
    }

    @objc private func togglePause() {
        isPaused.toggle()
        // Avoid judging Enter on stale composing state from before the
        // pause boundary: prefer a fresh start over a guess either way.
        composingKeyCount = 0
        refresh()
    }

    @objc private func quit() {
        exit(0)
    }
}

var statusMenuController: StatusMenuController?

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
            tapHealthy = CGEvent.tapIsEnabled(tap: tap)
            statusMenuController?.refresh()
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

    // Paused: pass everything through untouched, including the AXRole
    // check and composing-state observation below — "do nothing" beats
    // a wrong guess while the user has explicitly asked us to stand down.
    guard !isPaused else { return Unmanaged.passRetained(event) }

    let keycode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    let flags   = event.flags
    let isCmd   = flags.contains(.maskCommand)
    let isShift = flags.contains(.maskShift)

    // --- Remap path: Enter / Cmd+Enter ---
    if keycode == KEYCODE_ENTER {
        if isShift && !isCmd { return Unmanaged.passRetained(event) }
        // Single-line field (role unavailable = fall back to the existing
        // allowlist+IME logic below, e.g. Electron apps that don't expose it).
        if focusedElementRole() == (kAXTextFieldRole as String) {
            return Unmanaged.passRetained(event)
        }
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
            print("  AXRole: \(String(describing: focusedElementRole()))")
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

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon / app switcher entry
statusMenuController = StatusMenuController()
app.run()
