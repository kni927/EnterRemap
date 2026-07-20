import Cocoa
import Carbon
import CoreGraphics
import ServiceManagement

// Core idea (CGEventTap + eventSourceStateID for IME-safe Enter remap)
// credited to: https://qiita.com/nate3870/items/51b196de9a07717d3952

// MARK: - Configuration

// Preset target apps offered as checkmark items in the "Target Apps"
// submenu. Adding a preset here only changes what's offered — it
// doesn't enable it; see PRESET_ENABLED_BY_DEFAULT below for what ships on.
let PRESET_TARGET_APPS: [(name: String, bundleID: String)] = [
    ("Claude", "com.anthropic.claudefordesktop"),
    ("ChatGPT", "com.openai.codex"),               // unified app, post-Codex merge
    ("ChatGPT Classic", "com.openai.chat"),        // legacy
    ("Gemini", "com.google.GeminiMacOS"),
    ("Discord", "com.hnc.Discord"),
]

// Seeded into UserDefaults on first launch only. Discord ships off —
// the user turns it on explicitly from the Target Apps submenu.
let PRESET_ENABLED_BY_DEFAULT: Set<String> = [
    "com.anthropic.claudefordesktop",
    "com.openai.codex",
    "com.openai.chat",
    "com.google.GeminiMacOS",
]

let ALLOWED_BUNDLE_IDS_KEY = "AllowedBundleIDs"
let CUSTOM_BUNDLE_IDS_KEY = "CustomBundleIDs"

func loadAllowedBundleIDs() -> Set<String> {
    if let saved = UserDefaults.standard.array(forKey: ALLOWED_BUNDLE_IDS_KEY) as? [String] {
        return Set(saved)
    }
    UserDefaults.standard.set(Array(PRESET_ENABLED_BY_DEFAULT), forKey: ALLOWED_BUNDLE_IDS_KEY)
    return PRESET_ENABLED_BY_DEFAULT
}

func saveAllowedBundleIDs() {
    UserDefaults.standard.set(Array(ALLOWED_BUNDLE_IDS), forKey: ALLOWED_BUNDLE_IDS_KEY)
}

// Bundle IDs the user typed into the "Add Custom App..." dialog, kept
// separately from ALLOWED_BUNDLE_IDS so an unchecked custom entry still
// reappears (unchecked) the next time the Target Apps submenu is built.
func loadCustomBundleIDs() -> [String] {
    UserDefaults.standard.array(forKey: CUSTOM_BUNDLE_IDS_KEY) as? [String] ?? []
}

func saveCustomBundleIDs(_ ids: [String]) {
    UserDefaults.standard.set(ids, forKey: CUSTOM_BUNDLE_IDS_KEY)
}

// Allowed target apps (bundle IDs). Loaded once at launch; the Target
// Apps submenu mutates this directly and persists it via
// saveAllowedBundleIDs() — everywhere else still just reads it as a Set.
var ALLOWED_BUNDLE_IDS: Set<String> = loadAllowedBundleIDs()

let KEYCODE_ENTER: CGKeyCode = 36
let KEYCODE_KEYPAD_ENTER: CGKeyCode = 76
let KEYCODE_BACKSPACE: CGKeyCode = 51
let KEYCODE_ESCAPE: CGKeyCode = 53

// Off by default: KeypadEnter passes through untouched (app default,
// usually send). Toggled from the menu; persisted so it survives restarts.
let REMAP_KEYPAD_ENTER_KEY = "RemapKeypadEnter"

func loadRemapKeypadEnter() -> Bool {
    UserDefaults.standard.bool(forKey: REMAP_KEYPAD_ENTER_KEY)
}

func saveRemapKeypadEnter(_ value: Bool) {
    UserDefaults.standard.set(value, forKey: REMAP_KEYPAD_ENTER_KEY)
}

var remapKeypadEnter: Bool = loadRemapKeypadEnter()

// SMAppService is itself the source of truth for login-item state — no
// UserDefaults flag of our own, so an external change (e.g. the user
// removing it from System Settings > Login Items) can't drift out of
// sync with the menu's checkmark.
func loginItemIsRegistered() -> Bool {
    SMAppService.mainApp.status == .enabled
}

func setLoginItemRegistered(_ enabled: Bool) {
    do {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    } catch {
        fputs("Failed to \(enabled ? "register" : "unregister") login item: \(error)\n", stderr)
    }
}

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

// One step below the default menu font, but NSFont.menuFont(ofSize:)
// bakes in extra leading tuned for full-size menus, which read as
// loosely spaced at a smaller size; plain systemFont keeps row height
// closer to the text.
let MENU_ITEM_FONT_SIZE: CGFloat = 12

func menuItemFont() -> NSFont {
    NSFont.systemFont(ofSize: MENU_ITEM_FONT_SIZE)
}

func menuItemTitle(_ text: String) -> NSAttributedString {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineHeightMultiple = 1.0
    paragraphStyle.paragraphSpacingBefore = 0
    paragraphStyle.paragraphSpacing = 0
    return NSAttributedString(string: text, attributes: [
        .font: menuItemFont(),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: paragraphStyle,
    ])
}

// Catches .app drops for the Add Custom App field. Making the
// NSTextField itself the drop target does not work — its field editor
// intercepts the drop (draggingUpdated fires on the field, but
// prepareForDragOperation/performDragOperation never do). Instead this
// transparent overlay sits in front of the field: it receives the drop,
// extracts the app's bundle id, and writes it into the field via
// onDrop. hitTest returns nil so mouse clicks fall through to the field
// (drag-destination hit-testing is independent of mouse hitTest, so the
// overlay stays click-through while remaining droppable). Returning true
// from performDragOperation consumes the drop, so NSTextField's default
// "insert the raw path as text" behavior does not also run.
final class DropOverlayView: NSView {
    var onDrop: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func hitTest(_ point: NSPoint) -> NSView? { return nil }
    override var acceptsFirstResponder: Bool { return false }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { return .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { return .copy }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { return true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = sender.draggingPasteboard.readObjects(
                  forClasses: [NSURL.self], options: nil)?.first as? URL,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return false }
        onDrop?(bundleID)
        return true
    }
}

// MARK: - Target apps submenu
// An NSMenu submenu: one checkmark item per app, toggled in place on
// click, plus an "Add Custom App..." item. Writes straight through to
// ALLOWED_BUNDLE_IDS and UserDefaults — no restart needed.
//
// The Add prompt uses NSAlert (restored from the Phase 9 known-good
// implementation). Phase 10 replaced it with a hand-built NSWindow to
// add drag-and-drop, but that regressed text rendering (typed/dropped
// text stored correctly yet never drawn), and an NSAlert variant that
// bundled a drop view in its accessory regressed the same way. This
// keeps the plain, proven NSAlert path; drag-and-drop is tracked
// separately in docs/KNOWN_ISSUES.md.
final class TargetAppsMenuController: NSObject {
    let submenu = NSMenu()

    override init() {
        super.init()
        rebuildSubmenu()
    }

    private func allTargetAppRows() -> [(name: String, bundleID: String)] {
        var rows = PRESET_TARGET_APPS
        let presetIDs = Set(PRESET_TARGET_APPS.map { $0.bundleID })
        for custom in loadCustomBundleIDs() where !presetIDs.contains(custom) {
            rows.append((name: "Custom", bundleID: custom))
        }
        return rows
    }

    private func rebuildSubmenu() {
        submenu.removeAllItems()
        for (name, bundleID) in allTargetAppRows() {
            let item = NSMenuItem(title: "", action: #selector(toggleBundleID(_:)), keyEquivalent: "")
            item.target = self
            item.attributedTitle = menuItemTitle("\(name) — \(bundleID)")
            item.identifier = NSUserInterfaceItemIdentifier(bundleID)
            item.state = ALLOWED_BUNDLE_IDS.contains(bundleID) ? .on : .off
            submenu.addItem(item)
        }
        submenu.addItem(NSMenuItem.separator())
        let addItem = NSMenuItem(title: "", action: #selector(promptAddCustomApp), keyEquivalent: "")
        addItem.target = self
        addItem.attributedTitle = menuItemTitle("Add Custom App…")
        submenu.addItem(addItem)

        // Presets can be toggled off but not removed; only user-added
        // custom apps get a Remove entry. Kept as a separate submenu so
        // it doesn't interfere with the click-to-toggle checkmark rows.
        let customIDs = loadCustomBundleIDs().filter { id in
            !PRESET_TARGET_APPS.contains { $0.bundleID == id }
        }
        if !customIDs.isEmpty {
            let removeParent = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            removeParent.attributedTitle = menuItemTitle("Remove Custom App")
            let removeMenu = NSMenu()
            for id in customIDs {
                let removeItem = NSMenuItem(title: "", action: #selector(removeCustomApp(_:)), keyEquivalent: "")
                removeItem.target = self
                removeItem.attributedTitle = menuItemTitle(id)
                removeItem.identifier = NSUserInterfaceItemIdentifier(id)
                removeMenu.addItem(removeItem)
            }
            removeParent.submenu = removeMenu
            submenu.addItem(removeParent)
        }
    }

    @objc private func toggleBundleID(_ sender: NSMenuItem) {
        guard let bundleID = sender.identifier?.rawValue else { return }
        if sender.state == .on {
            sender.state = .off
            ALLOWED_BUNDLE_IDS.remove(bundleID)
        } else {
            sender.state = .on
            ALLOWED_BUNDLE_IDS.insert(bundleID)
        }
        saveAllowedBundleIDs()
    }

    @objc private func removeCustomApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.identifier?.rawValue else { return }
        saveCustomBundleIDs(loadCustomBundleIDs().filter { $0 != bundleID })
        ALLOWED_BUNDLE_IDS.remove(bundleID)
        saveAllowedBundleIDs()
        rebuildSubmenu()
    }

    @objc private func promptAddCustomApp() {
        let alert = NSAlert()
        alert.messageText = "Add Custom App"
        alert.informativeText = """
            Enter the target app's bundle identifier.

            To look it up, run one of these in Terminal:
              mdls -name kMDItemCFBundleIdentifier /Applications/<AppName>.app
              osascript -e 'id of app "<AppName>"'
            """
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        // Single-line: this is a 24pt single-line field, so a multi-line
        // placeholder (newlines) can't render here; one line conveys both
        // input methods.
        field.placeholderString = "Input Bundle Identifier or Drag and Drop App"

        // Transparent overlay in front of the field to catch .app drops;
        // it writes the extracted bundle id into the field.
        let overlay = DropOverlayView(frame: field.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.onDrop = { bundleID in field.stringValue = bundleID }

        let container = NSView(frame: field.frame)
        container.addSubview(field)
        container.addSubview(overlay) // in front of the field

        alert.accessoryView = container
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let bundleID = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty else { return }

        if !PRESET_TARGET_APPS.contains(where: { $0.bundleID == bundleID }) {
            var custom = loadCustomBundleIDs()
            if !custom.contains(bundleID) {
                custom.append(bundleID)
                saveCustomBundleIDs(custom)
            }
        }
        ALLOWED_BUNDLE_IDS.insert(bundleID) // newly typed = immediately enabled
        saveAllowedBundleIDs()
        rebuildSubmenu()
    }
}

final class StatusMenuController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "", action: #selector(togglePause), keyEquivalent: "")
    private let keypadEnterItem = NSMenuItem(title: "", action: #selector(toggleRemapKeypadEnter), keyEquivalent: "")
    private let loginItemItem = NSMenuItem(title: "", action: #selector(toggleLoginItem), keyEquivalent: "")
    private let targetAppsController = TargetAppsMenuController()

    override init() {
        super.init()
        let menu = NSMenu()
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(NSMenuItem.separator())
        let targetAppsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        targetAppsItem.attributedTitle = menuItemTitle("Target Apps")
        targetAppsItem.submenu = targetAppsController.submenu
        menu.addItem(targetAppsItem)
        keypadEnterItem.target = self
        keypadEnterItem.attributedTitle = menuItemTitle("Remap Keypad Enter")
        keypadEnterItem.state = remapKeypadEnter ? .on : .off
        menu.addItem(keypadEnterItem)
        pauseItem.target = self
        menu.addItem(pauseItem)
        loginItemItem.target = self
        loginItemItem.attributedTitle = menuItemTitle("Open at Login")
        // Read actual SMAppService status rather than trusting any
        // cached/persisted flag, so this can't drift if the user
        // toggled it from System Settings directly.
        loginItemItem.state = loginItemIsRegistered() ? .on : .off
        menu.addItem(loginItemItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.attributedTitle = menuItemTitle("Quit")
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
        pauseItem.attributedTitle = menuItemTitle(isPaused ? "Resume" : "Pause")
    }

    @objc private func togglePause() {
        isPaused.toggle()
        // Avoid judging Enter on stale composing state from before the
        // pause boundary: prefer a fresh start over a guess either way.
        composingKeyCount = 0
        refresh()
    }

    @objc private func toggleRemapKeypadEnter() {
        remapKeypadEnter.toggle()
        saveRemapKeypadEnter(remapKeypadEnter)
        keypadEnterItem.state = remapKeypadEnter ? .on : .off
    }

    @objc private func toggleLoginItem() {
        let enable = loginItemItem.state != .on
        setLoginItemRegistered(enable)
        // Reflect the actual resulting status: register()/unregister()
        // can fail (e.g. user declines in the system prompt), so don't
        // just assume the toggle succeeded.
        loginItemItem.state = loginItemIsRegistered() ? .on : .off
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
    // When enabled, KeypadEnter runs through the exact same checks and
    // transformation as the main Return key (IME/AXRole judgment included).
    if keycode == KEYCODE_ENTER || (remapKeypadEnter && keycode == KEYCODE_KEYPAD_ENTER) {
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
