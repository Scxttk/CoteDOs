import SwiftUI

/// A tab's glyph.
struct TabIcon: View {
    let tab: NotchViewModel.Tab
    var dimmed = false

    var body: some View {
        Image(systemName: tab.icon)
    }
}

struct NotchTabBar: View {
    @Binding var selection: NotchViewModel.Tab
    /// When false (`.solo`/`.condensing`), only the selected tab is present —
    /// the others have left the layout, letting the capsule narrow onto it.
    let showsAllTabs: Bool
    /// When false (`.condensing`), the labels drop and only the icon remains.
    let showsLabels: Bool
    /// Observed so the bar re-renders live when tabs are toggled in Settings.
    @ObservedObject private var settings = UserSettings.shared

    /// Shrinks the full row when the enabled tabs would overflow the island —
    /// only ever in the states that show all of them. Solo and condensing keep
    /// scale 1, because their metrics are tuned to hand the selected icon over
    /// to the pill glyph pixel for pixel; animating back to 1 as the row goes
    /// solo also brings that icon up to its final size just in time.
    private var fitScale: CGFloat {
        guard showsAllTabs else { return 1 }
        return NotchLayout.tabBarFitScale(titles: NotchViewModel.enabledTabs.map(\.title))
    }

    var body: some View {
        let scale = fitScale
        HStack(spacing: NotchLayout.tabBarSpacing) {
            ForEach(NotchViewModel.enabledTabs, id: \.self) { value in
                tab(title: value.title, value: value)
            }
        }
        .scaleEffect(scale)
        .animation(NotchLayout.condenseFadeAnimation, value: scale)
    }

    @ViewBuilder
    private func tab(title: String, value: NotchViewModel.Tab) -> some View {
        if showsAllTabs || selection == value {
            let isSelected = selection == value
            // Solo/condensing (this is the only tab): pin the *icon* at the
            // capsule centre — exactly where the pill icon will sit — so that
            // collapsing further only fades the label and shrinks the capsule;
            // the icon never moves again and the pill handover is pixel-exact.
            let soloMode = !showsAllTabs
            Button {
                guard selection != value else { return }
                Haptics.perform(.alignment)
                withAnimation(NotchLayout.tabChangeAnimation) { selection = value }
            } label: {
                HStack(spacing: NotchLayout.tabIconLabelSpacing) {
                    if soloMode {
                        // An invisible mirror of the real label, left of the
                        // icon: it reserves exactly the label's own width (real
                        // text metrics, no estimate), so the symmetric HStack
                        // centres the icon precisely. `.opacity(0)` (not
                        // `.hidden()`, which drops its layout space here) keeps
                        // the space through the label fade, so the icon holds
                        // dead centre — no wander, no flicker at the handover.
                        Text(title).fixedSize().opacity(0)
                    }
                    // Every icon renders itself, always — switching tabs must only
                    // change the highlight (foreground opacity), never replace or
                    // move the icon view, or it visibly pops back in.
                    TabIcon(tab: value, dimmed: !isSelected)
                    // The label stays in the layout even when hidden (fixed size,
                    // opacity only) so the mirror stays balanced; it just fades
                    // fast while the capsule narrows over it.
                    Text(title)
                        .fixedSize()
                        .opacity(showsLabels ? 1 : 0)
                        .animation(NotchLayout.condenseFadeAnimation, value: showsLabels)
                }
                .font(.system(size: NotchLayout.bandFontSize, weight: .medium))
                .padding(.vertical, NotchLayout.tabItemPaddingVertical)
                .padding(.horizontal, NotchLayout.tabItemPaddingHorizontal)
                .foregroundStyle(.white.opacity(isSelected ? 1 : NotchLayout.tabInactiveOpacity))
            }
            .buttonStyle(.plain)
            // Insertion waits for the selected icon's flight to its slot to
            // finish (it crosses the other tabs' positions on the way);
            // removal on collapse stays immediate — the capsule narrows fast
            // and lingering neighbours would get clipped against its rim.
            .transition(.asymmetric(
                insertion: .opacity.animation(
                    NotchLayout.condenseFadeAnimation.delay(NotchLayout.tabJoinFadeDelay)),
                removal: .opacity.animation(NotchLayout.condenseFadeAnimation)
            ))
        }
    }
}
