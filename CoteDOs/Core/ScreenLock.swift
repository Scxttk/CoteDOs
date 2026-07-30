import AppKit

/// Locking the Mac, the way the Lock Screen menu item does.
///
/// There is no public API for it. `SACLockScreenImmediate` in
/// `login.framework` is what Apple's own menu item calls and has been there
/// for a decade, but it is private and only reachable through `dlsym` — the
/// framework isn't even a file on disk any more (macOS 26 keeps it in the dyld
/// shared cache), which is exactly why the lookup is done by path *and* the
/// call sits behind a fallback: synthesizing ⌃⌘Q, the system shortcut for the
/// same thing. If both fail nothing happens, which is the right failure — a
/// screensaver that can't lock is still a screensaver.
enum ScreenLock {

    private static let loginFrameworkPath =
        "/System/Library/PrivateFrameworks/login.framework/Versions/A/login"

    @discardableResult
    static func lockNow() -> Bool {
        if lockViaLoginFramework() { return true }
        return lockViaShortcut()
    }

    private static func lockViaLoginFramework() -> Bool {
        typealias LockScreen = @convention(c) () -> Int32
        guard let handle = dlopen(loginFrameworkPath, RTLD_LAZY) else { return false }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "SACLockScreenImmediate") else { return false }
        return unsafeBitCast(symbol, to: LockScreen.self)() == 0
    }

    /// ⌃⌘Q. Needs the Accessibility grant the volume-key tap already asks for,
    /// and the shortcut has to still be assigned — hence the fallback slot
    /// rather than the first choice.
    private static func lockViaShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 0x0C, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x0C, keyDown: false)
        else { return false }
        down.flags = [.maskCommand, .maskControl]
        up.flags = [.maskCommand, .maskControl]
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
