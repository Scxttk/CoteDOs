import Combine
import IOKit.ps

/// Whether the Mac is running off its battery right now.
///
/// Exists so the wave can spend differently depending on where the power comes
/// from. Plugged in it eases between spectrum updates, the way it always has.
/// On battery that easing is dropped: a SwiftUI animation in flight forces a
/// re-evaluation on every 60 Hz display refresh regardless of how often the
/// bands actually change, and it is by a wide margin the most expensive thing
/// this app does — even after the `Canvas` rewrite collapsed the per-frame
/// cost, the always-in-flight ease still measured 25–28% of a core against
/// 9–11% without it, same signal, same machine, alternating builds.
/// Everything else about the wave is identical in both
/// modes; only the interpolation between frames goes away, which reads as a
/// visibly harder, stepped motion.
///
/// IOKit power-source run-loop notifications, no polling — the same mechanism
/// `BatteryActivityProvider` uses. Unlike the app's other models this starts
/// itself in `init` rather than from `AppDelegate`: it's a process-lifetime
/// singleton read from a view body, and the alternative (starting it in
/// `applicationDidFinishLaunching`) would leave it dead under XCTest, where
/// that method returns early.
final class PowerSource: ObservableObject {
    static let shared = PowerSource()

    /// False while on wall power, and while the power source can't be read at
    /// all (a desktop Mac, or an unexpected IOKit shape) — failing to the
    /// better-looking mode rather than to the cheaper one.
    @Published private(set) var isOnBattery = false

    private var runLoopSource: CFRunLoopSource?

    private init() {
        evaluate()
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            Unmanaged<PowerSource>.fromOpaque(ctx).takeUnretainedValue().evaluate()
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private func evaluate() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = list.first,
              let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any],
              let state = desc[kIOPSPowerSourceStateKey] as? String
        else {
            if isOnBattery { isOnBattery = false }
            return
        }
        let onBattery = (state == kIOPSBatteryPowerValue)
        if onBattery != isOnBattery { isOnBattery = onBattery }
    }
}
