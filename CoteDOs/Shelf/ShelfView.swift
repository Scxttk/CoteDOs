import SwiftUI

struct ShelfView: View {
    @ObservedObject var shelf: FileShelfModel

    var body: some View {
        ZStack {
            // Dashed frame only as live drop feedback; otherwise solid black.
            if shelf.isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                    .foregroundStyle(.white.opacity(0.85))
            }

            if shelf.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 20))
                    Text(String(localized: "shelf.dropHint", defaultValue: "Dateien hierher ziehen"))
                        .font(.system(size: 11))
                }
                .foregroundStyle(.white.opacity(0.45))
            } else {
                // `minWidth: geo.size.width` is what centres the row. A plain
                // horizontal `ScrollView` lays its content out from the leading
                // edge, so four files sat hard left with half the page empty
                // beside them — and it still scrolls the moment they outgrow it.
                GeometryReader { geo in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(shelf.items) { item in
                                ShelfItemView(item: item, shelf: shelf)
                            }
                        }
                        .padding(6)
                        .frame(minWidth: geo.size.width, alignment: .center)
                    }
                    .frame(height: geo.size.height)
                }
            }
        }
        // An overlay, not a row of its own above the shelf: as a row it took
        // height off the top and pushed the files below centre, to say something
        // about a control that is one glyph.
        .overlay(alignment: .topTrailing) {
            if !shelf.items.isEmpty {
                Button(action: shelf.clear) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.45))
                .help(String(localized: "shelf.clear", defaultValue: "Ablage leeren"))
                .accessibilityLabel(String(localized: "shelf.clear", defaultValue: "Ablage leeren"))
            }
        }
    }
}

private struct ShelfItemView: View {
    @ObservedObject var item: ShelfItem
    @ObservedObject var shelf: FileShelfModel

    var body: some View {
        VStack(spacing: 2) {
            Group {
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 44, height: 44)
            .overlay(alignment: .topTrailing) {
                if item.isMissing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.yellow)
                }
            }

            Text(item.name)
                .font(.system(size: 8))
                .lineLimit(1)
                .frame(width: 50)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(4)
        .opacity(item.isMissing ? 0.5 : 1)
        .help(item.isMissing
              ? String(localized: "shelf.missing", defaultValue: "Datei nicht gefunden") + " — " + item.name
              : item.name)
        .onDrag {
            // Don't hand over a file that no longer exists.
            guard shelf.refreshExistence(of: item) else { return NSItemProvider() }
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .contextMenu {
            ShareLink(item: item.url) {
                Label(String(localized: "shelf.share", defaultValue: "Teilen …"), systemImage: "square.and.arrow.up")
            }
            Button(String(localized: "shelf.remove", defaultValue: "Entfernen"), role: .destructive) { shelf.remove(item) }
        }
    }
}
