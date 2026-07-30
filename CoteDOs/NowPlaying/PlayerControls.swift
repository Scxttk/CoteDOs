import AppKit
import SwiftUI

/// A pointing-hand cursor while hovering, for clickable non-button surfaces.
struct PointingHandCursor: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        content.onHover { inside in
            if enabled, inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

extension View {
    func pointingHandCursor(enabled: Bool) -> some View {
        modifier(PointingHandCursor(enabled: enabled))
    }
}

/// Transport button with a hover highlight (visible when expanded).
struct ControlButton: View {
    let systemName: String
    var size: CGFloat
    var color: Color = .white
    /// Spoken name. Required rather than optional on purpose: a `Button` whose
    /// label is only an `Image(systemName:)` announces nothing at all to
    /// VoiceOver, so every transport control here was silent, and an argument you
    /// can forget is an argument that gets forgotten.
    let label: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size))
                .foregroundStyle(color)
                .frame(width: 34, height: 32)
                .background(
                    Circle().fill(Color.white.opacity(hovering ? 0.16 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
