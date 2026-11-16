import AppKit
import ColCore
import SwiftUI

/// A line of lyrics. Timed word by word, the line being sung fills from left to right as the voice goes, as a
/// karaoke screen does; otherwise it shows whole. The fill is redrawn thirty times a second, and only for the line
/// being sung while the music plays.
struct SungLine: View {
    let line: LyricLine
    /// The line's karaoke, or nil to show it whole.
    var karaoke: KaraokeLine?
    let size: CGFloat
    var weight: Font.Weight = .bold
    var alignment: HorizontalAlignment = .leading
    var lit: Color = .white
    var unlit: Color = .white.opacity(0.38)
    /// True while this is the line being sung and the music plays: the fill moves.
    var moving = false
    /// Where the song is at a date, for the fill.
    var position: (Date) -> TimeInterval = { _ in 0 }
    var lineLimit = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let karaoke {
            if moving {
                // With Reduce Motion the words light up whole: ten looks a second are plenty.
                TimelineView(.animation(minimumInterval: reduceMotion ? 0.1 : 1.0 / 30, paused: false)) { context in
                    words(karaoke, at: position(context.date))
                }
            } else {
                words(karaoke, at: position(Date()))
            }
        } else {
            Text(verbatim: line.text)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(lit)
                .multilineTextAlignment(alignment == .center ? .center : alignment == .trailing ? .trailing : .leading)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func words(_ karaoke: KaraokeLine, at time: TimeInterval) -> some View {
        WordFlow(alignment: alignment, space: size * 0.27, lineSpacing: size * 0.12) {
            ForEach(Array(karaoke.words.enumerated()), id: \.offset) { _, word in
                // With Reduce Motion, a word lights up whole as it starts, without the sweep.
                let fill = reduceMotion ? (word.fill(at: time) > 0 ? 1 : 0) : word.fill(at: time)
                FilledWord(text: word.text, fill: fill, size: size, weight: weight, lit: lit, unlit: unlit)
                    .animation(reduceMotion ? .easeOut(duration: 0.2) : nil, value: fill)
                    .layoutValue(key: SpaceAfter.self, value: word.spaceAfter)
            }
        }
    }
}

/// One word: dim, with its sung part bright. The edge between the two is soft, a little wider than a letter.
private struct FilledWord: View {
    let text: String
    let fill: Double
    let size: CGFloat
    let weight: Font.Weight
    let lit: Color
    let unlit: Color

    var body: some View {
        let label = Text(verbatim: text).font(.system(size: size, weight: weight))
        label
            .foregroundStyle(unlit)
            .overlay {
                if fill > 0 {
                    label
                        .foregroundStyle(lit)
                        .mask { mask }
                }
            }
            .fixedSize()
    }

    private var mask: some View {
        let edge = 0.14
        let middle = fill * (1 + edge) - edge / 2
        return LinearGradient(stops: [
            .init(color: .black, location: min(max(middle - edge / 2, 0), 1)),
            .init(color: .clear, location: min(max(middle + edge / 2, 0), 1)),
        ], startPoint: .leading, endPoint: .trailing)
    }
}

/// Whether a space follows a word: not between the pieces of a line written without spaces.
struct SpaceAfter: LayoutValueKey {
    static let defaultValue = true
}

/// Words in rows, wrapped like text, each row aligned as the line is.
struct WordFlow: Layout {
    var alignment: HorizontalAlignment = .leading
    var space: CGFloat
    var lineSpacing: CGFloat

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let gap = rows[rows.count - 1].indices.last.map { subviews[$0][SpaceAfter.self] ? space : 0 } ?? 0
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + gap + size.width > width {
                rows.append(Row())
            }
            let current = rows.count - 1
            let lead = rows[current].indices.isEmpty ? 0 : gap
            rows[current].indices.append(index)
            rows[current].width += lead + size.width
            rows[current].height = max(rows[current].height, size.height)
        }
        return rows.filter { !$0.indices.isEmpty }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(subviews, width: width)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width.map { min($0, widest) } ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x: CGFloat = switch alignment {
            case .center: bounds.minX + (bounds.width - row.width) / 2
            case .trailing: bounds.maxX - row.width
            default: bounds.minX
            }
            for (position, index) in row.indices.enumerated() {
                let size = subviews[index].sizeThatFits(.unspecified)
                if position > 0, subviews[row.indices[position - 1]][SpaceAfter.self] { x += space }
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width
            }
            y += row.height + lineSpacing
        }
    }
}

/// A few lines of lyrics around the one being sung, which sits on a reading line: the lines before it above, dim and
/// smaller, the lines to come below. When the next line starts, every line glides up on a spring and the sung one
/// grows into place; with Reduce Motion, the lines change with a simple fade.
struct LyricsReel: View {
    let lyrics: Lyrics
    let current: Int?
    let playing: Bool
    var position: (Date) -> TimeInterval
    var before = 1
    var after = 2
    /// The size of the line being sung; the others are drawn at `otherScale` of it.
    let size: CGFloat
    var otherScale: CGFloat = 0.62
    var alignment: HorizontalAlignment = .center
    /// Where the line being sung sits, from the top of the reel (0) to its bottom (1): its centre, or its top when
    /// `anchorsTop` is set, so a long line grows downward and never leaves the reel.
    var anchor: CGFloat = 0.4
    var anchorsTop = false
    var spacing: CGFloat = 14
    /// For lyrics drawn straight on a wallpaper: words a little brighter, with a shadow under them, so they read on
    /// light and busy pictures too.
    var onWallpaper = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let range = lyrics.neighbourhood(of: current, before: before, after: after)
        let focus = current ?? (range.lowerBound - 1)
        ReelLayout(anchor: anchor, anchorsTop: anchorsTop, spacing: spacing, otherScale: otherScale, alignment: alignment) {
            ForEach(range, id: \.self) { index in
                reelLine(index, distance: index - focus)
                    .id(lyrics.lines[index].id)
                    .layoutValue(key: ReelDistance.self, value: index - focus)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.3) : .spring(duration: 0.6, bounce: 0.14), value: current)
    }

    @ViewBuilder
    private func reelLine(_ index: Int, distance: Int) -> some View {
        let line = lyrics.lines[index]
        let sung = distance == 0
        // The lines are drawn at the size of the sung one and scaled: growing into place, a line keeps its letters.
        let scale = sung ? 1 : otherScale
        Group {
            if line.isPause {
                PulsingDots(color: .white, dot: size * 0.36, spacing: size * 0.3, motion: .swell, active: sung && playing)
                    .frame(height: size * 1.1)
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
            } else {
                SungLine(line: line, karaoke: sung ? lyrics.karaoke(at: index) : nil, size: size, alignment: alignment,
                         unlit: .white.opacity(onWallpaper ? 0.62 : 0.34), moving: sung && playing, position: position, lineLimit: sung ? 3 : 2)
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
            }
        }
        // A tight shadow outlines the letters, a wide one darkens the picture around them.
        .shadow(color: .black.opacity(onWallpaper ? 0.5 : 0), radius: onWallpaper ? 1.5 : 0, y: onWallpaper ? 1 : 0)
        .shadow(color: .black.opacity(onWallpaper ? 0.35 : 0), radius: onWallpaper ? size * 0.35 : 0)
        .scaleEffect(scale, anchor: scaleAnchor)
        .opacity(opacity(distance))
        .blur(radius: sung || reduceMotion || onWallpaper ? 0 : min(CGFloat(abs(distance)) * 0.6, 1.6))
    }

    private func opacity(_ distance: Int) -> Double {
        switch distance {
        case 0: 1
        case ..<0: onWallpaper ? 0.6 : 0.32
        case 1: onWallpaper ? 0.8 : 0.55
        default: onWallpaper ? 0.6 : 0.36
        }
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }

    private var scaleAnchor: UnitPoint {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }
}

/// How far a line is from the one being sung: 0 for it, negative above.
struct ReelDistance: LayoutValueKey {
    static let defaultValue = 0
}

/// Stacks the lines around the sung one, which is centred on the anchor; scaled lines take their scaled height.
private struct ReelLayout: Layout {
    let anchor: CGFloat
    let anchorsTop: Bool
    let spacing: CGFloat
    let otherScale: CGFloat
    let alignment: HorizontalAlignment

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 400, height: proposal.height ?? 300)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Each line laid out at full size over the width it will have once scaled, then counted at its scaled height.
        let measured = subviews.map { subview -> (distance: Int, scale: CGFloat, size: CGSize) in
            let distance = subview[ReelDistance.self]
            let scale = distance == 0 ? 1 : otherScale
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width / scale, height: nil))
            return (distance, scale, size)
        }
        let anchorY = bounds.minY + bounds.height * anchor
        var centres = [CGFloat](repeating: 0, count: subviews.count)
        // The sung line, or the place it would have just above the first line to come.
        let focus = measured.firstIndex { $0.distance == 0 }
        var below = anchorY
        var above = anchorY
        if let focus {
            let height = measured[focus].size.height
            let centre = anchorsTop ? anchorY + height / 2 : anchorY
            centres[focus] = centre
            below = centre + height / 2 + spacing
            above = centre - height / 2 - spacing
        }
        for index in measured.indices where measured[index].distance > 0 {
            let height = measured[index].size.height * measured[index].scale
            centres[index] = below + height / 2
            below += height + spacing
        }
        for index in measured.indices.reversed() where measured[index].distance < 0 {
            let height = measured[index].size.height * measured[index].scale
            centres[index] = above - height / 2
            above -= height + spacing
        }
        for index in subviews.indices {
            let width = bounds.width / measured[index].scale
            let x: CGFloat = switch alignment {
            case .center: bounds.midX
            case .trailing: bounds.maxX - width / 2
            default: bounds.minX + width / 2
            }
            subviews[index].place(at: CGPoint(x: x, y: centres[index]), anchor: .center,
                                  proposal: ProposedViewSize(width: width, height: measured[index].size.height))
        }
    }
}
