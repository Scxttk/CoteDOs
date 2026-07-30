import SwiftUI

extension AnyTransition {
    /// Content transition decoupled from the silhouette spring: content grows in
    /// (opacity + subtle scale, slightly delayed) and fades out fast on collapse,
    /// so it never lingers outside the shrinking shape.
    static var notchContent: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: NotchLayout.contentMorphScale, anchor: .top))
                .animation(NotchLayout.contentInsertAnimation),
            removal: .opacity.animation(NotchLayout.contentRemoveAnimation)
        )
    }

    /// The pill ⇄ condensed-icon handover: a hard, atomic cut. The two views
    /// are near-pixel-identical by construction (same glyph, same size, same
    /// centre — and the swap fires only once the condensed icon has settled,
    /// see `condenseSwapDelay`), so a one-frame swap is invisible. Any
    /// overlap-based scheme is *not*: holding both copies opaque for ~0.1 s means
    /// sub-point offsets between the two view trees make the union read as the
    /// glyph bolding up and thinning back — a visible end-of-collapse blink, and
    /// measurable on recorded frames as white pixel energy doubling for ~4 frames.
    static var iconHandover: AnyTransition { .identity }

    /// Cross-dissolve used when music plays and the tab bar hands off to the
    /// now-playing pill hero (cover + spectrum) — in both directions. The
    /// arriving side starts slightly later (`heroCrossfadeInsertDelay`) so the
    /// capsule has begun growing toward its size before its content fades in;
    /// the departing side's fade covers the delay, so nothing shows empty.
    static var heroCrossfade: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(
                .easeInOut(duration: NotchLayout.heroCrossfadeDuration)
                    .delay(NotchLayout.heroCrossfadeInsertDelay)),
            removal: .opacity.animation(.easeInOut(duration: NotchLayout.heroCrossfadeDuration))
        )
    }
}
