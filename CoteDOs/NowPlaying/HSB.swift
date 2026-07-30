import AppKit
import SwiftUI

/// A colour taken apart into hue/saturation/brightness *once*.
///
/// Every shading helper the wave uses (whiten a bar's tip, dim its foot, mix
/// two accents) needs those components, and getting them out of a SwiftUI
/// `Color` means `NSColor(color).usingColorSpace(.deviceRGB)` — a ColorSync
/// round-trip. That is nothing once per palette and ruinous per bar per frame:
/// a `sample` of the running app had `ColorSyncProfileGetTag` and friends at
/// the top of the main thread, because the 32-bar pill wave was re-deriving
/// every bar's colour 30×/s. So the round-trip happens where the colour is
/// *decided* (cover palette, accent) and everything downstream is arithmetic.
struct HSB: Equatable {
    var h: CGFloat
    var s: CGFloat
    var b: CGFloat

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        self.h = h
        self.s = s
        self.b = b
    }

    init(h: CGFloat, s: CGFloat, b: CGFloat) {
        self.h = h
        self.s = s
        self.b = b
    }

    var color: Color { Color(hue: h, saturation: s, brightness: b) }

    /// Same hue and saturation, brightness scaled by `factor` (clamped).
    func brightnessScaled(_ factor: Double) -> Color {
        Color(hue: h, saturation: s, brightness: min(1, max(0.1, b * CGFloat(factor))))
    }

    /// Same hue, saturation and brightness each scaled — the two axes a
    /// spectrum bar's vertical gradient actually travels along.
    func scaled(saturation sFactor: Double, brightness bFactor: Double) -> Color {
        scaledHSB(saturation: sFactor, brightness: bFactor).color
    }

    /// Same scaling, kept in components — callers that need to interpolate the
    /// result (the wave's foot colour on very tall bars) would otherwise have to
    /// decompose the `Color` again, which is a ColorSync round-trip.
    func scaledHSB(saturation sFactor: Double, brightness bFactor: Double) -> HSB {
        HSB(
            h: h,
            s: min(1, max(0, s * CGFloat(sFactor))),
            b: min(1, max(0.1, b * CGFloat(bFactor)))
        )
    }

    /// Interpolation toward `other`, hue travelling the *shortest arc* — RGB
    /// interpolation between two saturated hues passes through the desaturated
    /// middle and turns the wave's centre to mud.
    func mixed(to other: HSB, t: Double) -> HSB {
        let fraction = CGFloat(max(0, min(1, t)))
        var dh = other.h - h
        if dh > 0.5 { dh -= 1 }
        if dh < -0.5 { dh += 1 }
        var hue = (h + dh * fraction).truncatingRemainder(dividingBy: 1)
        if hue < 0 { hue += 1 }
        return HSB(
            h: hue,
            s: s + (other.s - s) * fraction,
            b: b + (other.b - b) * fraction
        )
    }
}
