import SwiftUI

/// Compact rendering of a live activity inside the collapsed pill.
struct ActivityCompactView: View {
    let activity: NotchActivity

    private var isRoute: Bool { activity.kind == .audioRoute }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: activity.icon)
                // The audio-route icon is bumped up so a connecting device reads
                // clearly at a glance (the main "markant" ask).
                .font(.system(size: isRoute ? 17 : 12, weight: .semibold))
                .foregroundStyle(activity.tint)
                .frame(width: isRoute ? 22 : 16)
            if let progress = activity.progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)))
                    }
                }
                .frame(height: 4)
            } else {
                Text(activity.title)
                    .font(.system(size: isRoute ? 12 : 11, weight: isRoute ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let detail = activity.detail {
                    BatteryBadge(text: detail)
                }
            }
        }
        .padding(.horizontal, isRoute ? 12 : 14)
        // Same fixed top band as CollapsedView, so activity content doesn't
        // drift vertically while the island morphs.
        .frame(height: NotchLayout.currentCollapsedHeight)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// A small tinted battery pill (icon + percentage), tinted red/orange when low.
struct BatteryBadge: View {
    let text: String

    private var level: Int? { Int(text.replacingOccurrences(of: "%", with: "")) }

    private var color: Color {
        switch level ?? 100 {
        case ..<15: return .red
        case ..<30: return .orange
        default: return .green
        }
    }

    private var symbol: String {
        switch level ?? 100 {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(color)
    }
}
