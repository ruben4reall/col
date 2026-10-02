import AppKit
import SwiftUI

/// Files dropped on the island. Drag them back out, open them, or send them all with AirDrop.
struct ShelfPage: View {
    let shelf: ShelfModel

    var body: some View {
        if shelf.items.isEmpty {
            DropHint(isTargeted: shelf.isTargeted)
        } else {
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shelf.items) { item in
                            ShelfTile(item: item, shelf: shelf)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(duration: 0.4, bounce: 0.25), value: shelf.items.map(\.url))
                }
                .overlay {
                    if shelf.isTargeted {
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                }
                VStack(spacing: 8) {
                    AirDropButton(enabled: shelf.canAirDrop) { shelf.airDrop() }
                    Button {
                        withAnimation(.spring(duration: 0.35)) { shelf.clear() }
                    } label: {
                        Text("Clear", bundle: .module)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }
}

private struct DropHint: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(isTargeted ? Theme.accent : Theme.secondaryText)
                .symbolEffect(.bounce, value: isTargeted)
            Text("Drop files on the notch", bundle: .module)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("They wait here until you drag them somewhere else.", bundle: .module)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(isTargeted ? Theme.accent : Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .animation(.easeOut(duration: 0.2), value: isTargeted)
    }
}

private struct ShelfTile: View {
    let item: ShelfModel.Item
    let shelf: ShelfModel
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 5) {
            Group {
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "doc.fill").font(.system(size: 30)).foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(width: 54, height: 54)
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            Text(item.url.lastPathComponent)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 70)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hovering ? 0.08 : 0)))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button {
                    withAnimation(.spring(duration: 0.3)) { shelf.remove(item) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.black, .white.opacity(0.85))
                }
                .buttonStyle(PressableStyle())
                .offset(x: 2, y: -2)
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { shelf.open(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button { shelf.open(item) } label: { Text("Open", bundle: .module) }
            Button { shelf.reveal(item) } label: { Text("Show in Finder", bundle: .module) }
            Divider()
            Button { shelf.remove(item) } label: { Text("Remove from shelf", bundle: .module) }
        }
        .help(item.url.path)
    }
}

private struct AirDropButton: View {
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if let icon = NSSharingService(named: .sendViaAirDrop)?.image {
                    Image(nsImage: icon).resizable().frame(width: 30, height: 30)
                }
                Text(verbatim: "AirDrop")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 70, height: 66)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(hovering ? 0.14 : 0.08)))
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovering = $0 }
    }
}
