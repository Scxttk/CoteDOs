import AppKit
import ApplicationServices

/// Detects Safari running fullscreen on some display — the one situation where
/// the centred pill sits right on top of the browser's search/URL bar (the
/// menu bar is gone, so the toolbar moves up under the notch). The pill can't
/// stay there: it is dodged to the right of the URL field and made
/// click-through for the duration (see `NotchWindowController`).
///
/// Modeled on `MenuBarOverlapMonitor`: reads the frontmost app through the
/// Accessibility API, reusing the permission already granted for the
/// volume-key tap, and fails open — no permission or any unexpected AX shape
/// simply reports "no dodge", leaving the pill centred as before. Fullscreen
/// is read from the focused window's `AXFullScreen` attribute (app-scoped and
/// immune to menu-bar-autohide false positives that a `visibleFrame`
/// heuristic would have).
final class SafariFullscreenMonitor {

    /// Safari is fullscreen on `screen`; `urlFieldMaxX` is the right edge of
    /// its address/search field in `NSScreen.frame` coordinates, or nil when
    /// the toolbar couldn't be resolved (dodge to a generic fallback then).
    struct DodgeState: Equatable {
        let screen: NSScreen
        let urlFieldMaxX: CGFloat?

        static func == (lhs: DodgeState, rhs: DodgeState) -> Bool {
            lhs.screen === rhs.screen && lhs.urlFieldMaxX == rhs.urlFieldMaxX
        }
    }

    /// Called on the main thread whenever the dodge state changes; nil means
    /// "no Safari fullscreen anywhere, pill returns to centre".
    var onChange: ((DodgeState?) -> Void)?

    private var activationObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var pollTimer: Timer?
    private(set) var current: DodgeState?

    private static let safariBundleID = "com.apple.Safari"
    private static let pollInterval: TimeInterval = 1.0
    /// How deep below the toolbar to search for the URL text field. Safari
    /// nests the field a few groups down; the cap keeps a changed hierarchy
    /// from turning into a full-tree walk.
    private static let toolbarSearchDepth = 5

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
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
        evaluate()
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        if let activationObserver { center.removeObserver(activationObserver) }
        if let spaceObserver { center.removeObserver(spaceObserver) }
        activationObserver = nil
        spaceObserver = nil
        pollTimer?.invalidate()
        pollTimer = nil
    }

    deinit { stop() }

    private func evaluate() {
        let state = computeDodgeState()
        guard state != current else { return }
        current = state
        onChange?(state)
    }

    // MARK: Positioning

    /// Where the dodged pill's centre belongs: just right of the URL field
    /// (or a generic offset right of centre when AX couldn't resolve it),
    /// clamped so the pill keeps clear of the screen's right edge.
    static func dodgePillCenterX(urlFieldMaxX: CGFloat?, screenFrame: NSRect, pillWidth: CGFloat) -> CGFloat {
        let centerX: CGFloat
        if let urlFieldMaxX {
            centerX = urlFieldMaxX + NotchLayout.safariDodgeGap + pillWidth / 2
        } else {
            centerX = screenFrame.midX + NotchLayout.safariDodgeFallbackOffset
        }
        return min(centerX, screenFrame.maxX - NotchLayout.safariDodgeEdgeMargin - pillWidth / 2)
    }

    // MARK: AX plumbing

    private func computeDodgeState() -> DodgeState? {
        guard MediaKeyTap.hasAccessibilityPermission(prompt: false) else { return nil }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == Self.safariBundleID
        else { return nil }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = elementAttribute(of: axApp, kAXFocusedWindowAttribute) else { return nil }

        var fullscreenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreenValue) == .success,
              let fullscreen = fullscreenValue as? Bool, fullscreen
        else { return nil }

        guard let windowFrame = frame(of: window),
              let screen = screenContaining(axRect: windowFrame)
        else { return nil }

        var urlFieldMaxX: CGFloat?
        if let toolbar = childWithRole(kAXToolbarRole as String, of: window),
           let field = descendantWithRole("AXTextField", of: toolbar, depth: Self.toolbarSearchDepth),
           let fieldFrame = frame(of: field) {
            // AX X coordinates share the axis with `NSScreen.frame`; only Y is
            // flipped (and irrelevant here). Rounded so per-poll sub-pixel
            // jitter doesn't churn the dodge state every second.
            urlFieldMaxX = (fieldFrame.maxX).rounded()
        }
        return DodgeState(screen: screen, urlFieldMaxX: urlFieldMaxX)
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

    private func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func childWithRole(_ role: String, of element: AXUIElement) -> AXUIElement? {
        children(of: element).first { self.role(of: $0) == role }
    }

    /// Depth-limited breadth-first search — Safari's toolbar nests the address
    /// field inside a couple of groups whose exact shape churns between
    /// versions, so match by role only.
    private func descendantWithRole(_ role: String, of element: AXUIElement, depth: Int) -> AXUIElement? {
        var frontier = children(of: element)
        var remaining = depth
        while !frontier.isEmpty, remaining > 0 {
            if let match = frontier.first(where: { self.role(of: $0) == role }) { return match }
            frontier = frontier.flatMap { children(of: $0) }
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
