import AppKit
import ApplicationServices

/// Detects Safari showing its search/URL bar under the notch on some display —
/// the one situation where the centred pill sits right on top of it (in
/// fullscreen the menu bar is gone, so the toolbar moves up under the notch).
/// The pill can't stay there: it is dodged to the right of the URL field and
/// made click-through for the duration (see `NotchWindowController`).
///
/// The trigger is the *visible URL field*, not fullscreen as such. A window
/// that reports fullscreen without a toolbar on screen — a video put fullscreen
/// from the page (`f` on YouTube/Twitch), or a toolbar Safari has auto-hidden —
/// has nothing for the pill to collide with, so it stays centred and
/// interactive.
///
/// Modeled on `MenuBarOverlapMonitor`: reads the frontmost app through the
/// Accessibility API, reusing the permission already granted for the
/// volume-key tap, and fails open — no permission or any unexpected AX shape
/// simply reports "no dodge", leaving the pill centred as before. Fullscreen
/// is read from the focused window's `AXFullScreen` attribute (app-scoped and
/// immune to menu-bar-autohide false positives that a `visibleFrame`
/// heuristic would have).
final class SafariFullscreenMonitor {

    /// Safari is fullscreen on `screen` with its address/search field visible;
    /// `urlFieldFrame` is that field in `NSScreen.frame` coordinates (Cocoa,
    /// origin bottom-left). The full frame — not just the right edge — because
    /// the dodged pill aligns vertically with the field's centre, nestling
    /// beside the toolbar instead of hugging the screen's top edge above it.
    struct DodgeState: Equatable {
        let screen: NSScreen
        let urlFieldFrame: NSRect

        static func == (lhs: DodgeState, rhs: DodgeState) -> Bool {
            lhs.screen === rhs.screen && lhs.urlFieldFrame == rhs.urlFieldFrame
        }
    }

    /// Called on the main thread whenever the dodge state changes; nil means
    /// "no Safari fullscreen anywhere, pill returns to centre".
    var onChange: ((DodgeState?) -> Void)?

    private var activationObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var pollTimer: Timer?
    private var pollInterval: TimeInterval = 0
    private(set) var current: DodgeState?

    private static let safariBundleID = "com.apple.Safari"
    /// The poll is only a fallback — app activation and Space changes already
    /// have notifications, and this catches the rest (a toolbar that moves
    /// without either). Every tick with Safari frontmost walks its AX tree
    /// across the process boundary, which wakes Safari too, so it runs at
    /// half the old rate; the dodge doesn't need sub-second latency for the
    /// cases no notification covers.
    private static let pollInterval: TimeInterval = 2.0
    /// The rate while Safari is frontmost *and* fullscreen. Putting a video
    /// fullscreen from the page hides the toolbar without an app switch or a
    /// Space change, so only the poll notices — and two seconds of the pill
    /// sitting off to the side is very visible. The cost of the faster rate is
    /// paid in the one state where it shows.
    private static let fullscreenPollInterval: TimeInterval = 0.5
    /// How deep below the toolbar to search for the URL text field. Safari
    /// nests the field a few groups down; the cap keeps a changed hierarchy
    /// from turning into a full-tree walk.
    private static let toolbarSearchDepth = 8

    /// Set by the last `computeDodgeState()`: Safari frontmost with a
    /// fullscreen focused window, dodged or not. Drives the poll rate.
    private var sawSafariFullscreen = false

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        activationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.evaluate() }
        // Entering/leaving a fullscreen Space happens without an app switch —
        // the overlap monitor doesn't need this trigger, this one does.
        spaceObserver = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.evaluate() }
        schedulePoll(interval: Self.pollInterval)
        evaluate()
    }

    private func schedulePoll(interval: TimeInterval) {
        guard pollInterval != interval || pollTimer == nil else { return }
        pollInterval = interval
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        if let activationObserver { center.removeObserver(activationObserver) }
        if let spaceObserver { center.removeObserver(spaceObserver) }
        activationObserver = nil
        spaceObserver = nil
        pollTimer?.invalidate()
        pollTimer = nil
        pollInterval = 0
    }

    deinit { stop() }

    private func evaluate() {
        let state = computeDodgeState()
        schedulePoll(interval: sawSafariFullscreen ? Self.fullscreenPollInterval : Self.pollInterval)
        guard state != current else { return }
        current = state
        onChange?(state)
    }

    /// Plain-file diagnostics (`/tmp/cotedos-dodge.log`): written only while
    /// Safari is frontmost, so a failing guard is visible without the unified
    /// log's redaction.
    ///
    /// Debug-only. "One line per second at most, cheap enough to stay on" was
    /// wrong twice over: it's two lines per poll, and each one opens, seeks,
    /// writes and closes the file. In a release build, with Safari frontmost
    /// all day, that ran forever and grew the log without bound (1.5 MB of
    /// "url field not found" when this was found).
    /// `@autoclosure` so a release build doesn't even build the interpolated
    /// string it would then throw away.
    private func dlog(_ message: @autoclosure () -> String) {
        #if DEBUG
        let line = "\(Date()) \(message())\n"
        let path = "/tmp/cotedos-dodge.log"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        #endif
    }

    // MARK: Positioning

    /// Where the dodged pill's centre belongs: just right of the URL field,
    /// clamped so the pill keeps clear of the screen's right edge.
    static func dodgePillCenterX(urlFieldMaxX: CGFloat, screenFrame: NSRect, pillWidth: CGFloat, gap: CGFloat = NotchLayout.safariDodgeGap) -> CGFloat {
        let centerX = urlFieldMaxX + gap + pillWidth / 2
        return min(centerX, screenFrame.maxX - NotchLayout.safariDodgeEdgeMargin - pillWidth / 2)
    }

    /// Is the field AX reported actually on screen and worth dodging?
    ///
    /// A hidden toolbar isn't always absent from the AX tree — Safari can park
    /// it above the top edge instead, where its frame reads as a sliver poking
    /// past `maxY`. Anything empty, off this display, or above the top edge is
    /// not something the pill can collide with.
    static func isURLFieldVisible(_ field: NSRect, on screenFrame: NSRect) -> Bool {
        guard field.width > 0, field.height > 0 else { return false }
        guard screenFrame.intersects(field) else { return false }
        return field.maxY <= screenFrame.maxY
    }

    // MARK: AX plumbing

    private func computeDodgeState() -> DodgeState? {
        // Cleared up front so every early exit below leaves the poll at the
        // idle rate; only the fullscreen guard sets it.
        sawSafariFullscreen = false
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == Self.safariBundleID
        else { return nil }
        guard MediaKeyTap.hasAccessibilityPermission(prompt: false) else {
            dlog("no accessibility permission")
            return nil
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = elementAttribute(of: axApp, kAXFocusedWindowAttribute) else {
            dlog("no focused window via AX")
            return nil
        }

        var fullscreenValue: CFTypeRef?
        let fullscreenResult = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreenValue)
        guard fullscreenResult == .success, let fullscreen = fullscreenValue as? Bool else {
            dlog("AXFullScreen unreadable (result \(fullscreenResult.rawValue))")
            return nil
        }
        guard fullscreen else {
            dlog("safari frontmost, not fullscreen")
            return nil
        }
        sawSafariFullscreen = true

        guard let windowFrame = frame(of: window) else {
            dlog("window frame unreadable")
            return nil
        }
        guard let screen = screenContaining(axRect: windowFrame) else {
            dlog("no screen for window frame \(windowFrame)")
            return nil
        }
        dlog("fullscreen on screen \(screen.frame)")

        // No visible URL field, no dodge. A video put fullscreen from the page
        // reports the window as fullscreen while the toolbar is gone — there
        // the pill belongs where it always is, centred and interactive.
        guard let field = urlField(in: window) else {
            dlog("no url field in the window, staying centred")
            return nil
        }
        guard !boolAttribute(of: field, kAXHiddenAttribute) else {
            dlog("url field hidden, staying centred")
            return nil
        }
        guard let fieldFrame = frame(of: field), let primary = NSScreen.screens.first else {
            dlog("url field frame unreadable, staying centred")
            return nil
        }
        // AX X coordinates share the axis with `NSScreen.frame`; Y is flipped
        // (AX origin top-left of the primary screen, Y down). Rounded so
        // per-poll sub-pixel jitter doesn't churn the dodge state every tick.
        let urlFieldFrame = NSRect(
            x: fieldFrame.origin.x.rounded(),
            y: (primary.frame.maxY - fieldFrame.maxY).rounded(),
            width: fieldFrame.width.rounded(),
            height: fieldFrame.height.rounded()
        )
        guard Self.isURLFieldVisible(urlFieldFrame, on: screen.frame) else {
            dlog("url field \(urlFieldFrame) not visible on \(screen.frame), staying centred")
            return nil
        }
        dlog("url field \(urlFieldFrame)")
        return DodgeState(screen: screen, urlFieldFrame: urlFieldFrame)
    }

    /// Convert an AX rect (origin top-left of the primary screen, Y down) far
    /// enough to find the display it lives on: X is shared, so match the rect's
    /// midpoint X plus the flipped midpoint Y against each screen's frame.
    private func screenContaining(axRect: CGRect) -> NSScreen? {
        guard let primary = NSScreen.screens.first else { return nil }
        let midPoint = NSPoint(
            x: axRect.midX,
            y: primary.frame.maxY - axRect.midY
        )
        return NSScreen.screens.first { $0.frame.contains(midPoint) }
            ?? NSScreen.screens.first { abs($0.frame.midX - axRect.midX) < $0.frame.width / 2 }
    }

    // The AX API returns CFTypeRef; every access checks the type ID instead of
    // force-casting, so an unexpected shape reads as "no dodge" (fail open)
    // rather than a crash — same pattern as `MenuBarOverlapMonitor`.

    private func elementAttribute(of element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement]
        else { return [] }
        return children
    }

    /// A missing or oddly-typed attribute reads as false — same fail-open
    /// stance as the rest of the AX plumbing.
    private func boolAttribute(of element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    private func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Safari's unified address/search field: the first `AXTextField` found by
    /// a depth-limited breadth-first walk of the *window* — not just of a
    /// top-level `AXToolbar` child, because in fullscreen the toolbar sits a
    /// few groups down and its position churns between Safari versions.
    /// Content subtrees (web area, sidebar, tab strip) are pruned so a text
    /// field on the page itself can never win.
    private func urlField(in window: AXUIElement) -> AXUIElement? {
        var frontier = [window]
        var remaining = Self.toolbarSearchDepth
        while !frontier.isEmpty, remaining > 0 {
            var next: [AXUIElement] = []
            for element in frontier {
                for child in children(of: element) {
                    switch role(of: child) {
                    case "AXTextField":
                        return child
                    case "AXWebArea", "AXScrollArea", "AXTabGroup":
                        continue
                    default:
                        next.append(child)
                    }
                }
            }
            frontier = next
            remaining -= 1
        }
        return nil
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, CFGetTypeID(positionValue) == AXValueGetTypeID(),
              let sizeValue, CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }
}
