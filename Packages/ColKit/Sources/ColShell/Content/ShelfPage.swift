import AppKit
import ColCore
import SwiftUI

/// Files dropped on the island. Drag them back out, open them, or send them all with AirDrop; from a file's menu,
/// convert or resize an image, compress files, or copy the text of an image.
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
                    if let notice = shelf.notice {
                        ShelfNoticeView(notice: notice)
                            .transition(.opacity)
                    } else {
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
                .frame(width: 70)
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
            if Preferences.shelfTools {
                ShelfToolsMenu(item: item, shelf: shelf)
            }
            Divider()
            Button { shelf.remove(item) } label: { Text("Remove from shelf", bundle: .module) }
        }
        .help(item.url.path)
    }
}

/// The tools of a file's menu: what can be done with this file, and nothing that cannot.
private struct ShelfToolsMenu: View {
    let item: ShelfModel.Item
    let shelf: ShelfModel

    var body: some View {
        Divider()
        let conversions = ShelfTools.conversions(for: item.url)
        if !conversions.isEmpty {
            Menu {
                ForEach(conversions, id: \.self) { format in
                    Button { shelf.convert(item, to: format) } label: { Text(verbatim: format.name) }
                }
            } label: {
                Text("Convert to", bundle: .module)
            }
            Menu {
                Button { shelf.resize(item, .half) } label: { Text("Half the Size (50 %)", bundle: .module) }
                Button { shelf.resize(item, .pointSize) } label: { Text("Retina Capture to 1x", bundle: .module) }
            } label: {
                Text("Resize", bundle: .module)
            }
            Button { shelf.copyText(item) } label: { Text("Copy Text from Image", bundle: .module) }
        }
        Button { shelf.compress([item]) } label: { Text("Compress", bundle: .module) }
        if shelf.items.count > 1 {
            Button { shelf.compress(shelf.items) } label: { Text("Compress All \(shelf.items.count) Files", bundle: .module) }
        }
    }
}

/// What a tool is doing, or what it did, in place of Clear for a moment.
private struct ShelfNoticeView: View {
    let notice: ShelfNotice

    var body: some View {
        VStack(spacing: 3) {
            if notice.working {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: notice.failed ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(notice.failed ? RGBA.orange.color : Theme.accent)
            }
            Text(verbatim: notice.text)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(Theme.secondaryText)
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
