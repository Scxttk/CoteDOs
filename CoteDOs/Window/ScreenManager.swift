import AppKit

enum ScreenManager {
    /// The screen the notch should currently live on: the one the cursor is on,
    /// so the island follows the user across a multi-display setup. Falls back to
    /// the menu-bar screen, then any screen.
    static func targetScreen() -> NSScreen? {
        let cursor = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
}
