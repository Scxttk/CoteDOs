import Carbon.HIToolbox

/// Quick Capture's global hotkey. Default: ⌥⌘Space.
///
/// A thin facade over `HotKeyCenter` — the Carbon plumbing moved there when a
/// second global hotkey (the fullscreen spectrum) arrived, because Carbon
/// delivers every hotkey press to every installed handler and the registration
/// therefore has to dispatch on the hotkey's id in one place.
final class CaptureHotKey {
    /// Invoked on the main thread when the hotkey is pressed.
    var onTrigger: (() -> Void)?

    func register(keyCode: UInt32 = UInt32(kVK_Space),
                  modifiers: UInt32 = UInt32(cmdKey | optionKey)) {
        HotKeyCenter.shared.register(.quickCapture, keyCode: keyCode, modifiers: modifiers) { [weak self] in
            self?.onTrigger?()
        }
    }

    func unregister() {
        HotKeyCenter.shared.unregister(.quickCapture)
    }

    deinit { unregister() }
}
