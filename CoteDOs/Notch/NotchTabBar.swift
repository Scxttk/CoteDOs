import SwiftUI

/// A tab's glyph.
struct TabIcon: View {
    let tab: NotchViewModel.Tab
    var dimmed = false

    var body: some View {
        Image(systemName: tab.icon)
            // Its own size, not the surrounding font's. Inheriting the label's
            // 13 pt is what made these read as tiny: an SF Symbol set at text
            // size next to that text is always the smaller-looking of the two.
            .font(.system(size: NotchLayout.tabIconSize, weight: .medium))
    }
}

/// The row of tabs across the top of the expanded island.
///
/// Icons only, no titles, and that is what buys the icons their size. Five
/// German titles come to ~472 pt against the 348 pt the band capsule offers, so
/// a labelled row has to be scaled to ~0.72 to fit — which shrinks the icons
/// along with the text and lands them at about 9 pt. Dropping the titles takes
/// the row to ~210 pt, no scaling at all, and leaves room to draw the glyphs
/// half again as large.
///
/// What the titles were doing, selection now does: the chosen tab sits in a
/// filled capsule, the way a segmented control marks its selection. The names
/// are still reachable — tooltip on hover, and VoiceOver reads them, which it
/// could not do before because the visible text *was* the accessible name.
struct NotchTabBar: View {
    @Binding var selection: NotchViewModel.Tab
    /// When false (`.solo`/`.condensing`), only the selected tab is present —
    /// the others have left the layout, letting the capsule narrow onto it.
    let showsAllTabs: Bool
    /// Observed so the bar re-renders live when tabs are toggled in Settings.
    @ObservedObject private var settings = UserSettings.shared

    var body: some View {
        HStack(spacing: NotchLayout.tabBarSpacing) {
            ForEach(NotchViewModel.enabledTabs, id: \.self) { value in
                tab(value)
            }
        }
        .padding(.top, showsAllTabs ? NotchLayout.tabBarTopInset : 0)
    }

    @ViewBuilder
    private func tab(_ value: NotchViewModel.Tab) -> some View {
        if showsAllTabs || selection == value {
            let isSelected = selection == value
            Button {
                guard selection != value else { return }
                Haptics.perform(.alignment)
                withAnimation(NotchLayout.tabChangeAnimation) { selection = value }
            } label: {
                // Every icon renders itself, always — switching tabs must only
                // change the highlight, never replace or move the icon view, or
                // it visibly pops back in.
                TabIcon(tab: value, dimmed: !isSelected)
                    .frame(width: NotchLayout.tabItemWidth,
                           height: NotchLayout.tabItemHeight)
                    .background {
                        // Behind the glyph rather than around it, so the capsule
                        // can appear and disappear without moving anything: every
                        // item holds the same frame whether selected or not.
                        Capsule(style: .continuous)
                            .fill(.white.opacity(isSelected ? NotchLayout.tabSelectionFill : 0))
                    }
                    .foregroundStyle(.white.opacity(isSelected ? 1 : NotchLayout.tabInactiveOpacity))
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .help(value.title)
            .accessibilityLabel(value.title)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
