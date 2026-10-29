import SwiftUI
import WidgetKit

/// 对应设计系统的 Progress：奶油底带网点纹理的胶囊轨道，实心填充，右侧剩余百分比
public struct LimitBar: View {
    @Environment(\.widgetInk) private var ink

    /// 剩余可用百分比，填充长度与右侧数字都按它计算
    public let remainingPercent: Double
    public var height: CGFloat
    /// 关掉之后只保留右侧百分比
    public var showsTrack: Bool

    public init(remainingPercent: Double, height: CGFloat = 14, showsTrack: Bool = true) {
        self.remainingPercent = remainingPercent
        self.height = height
        self.showsTrack = showsTrack
    }

    public var body: some View {
        HStack(spacing: 10) {
            if showsTrack {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        track
                        fill(width: geometry.size.width * remainingPercent / 100)
                    }
                }
                .frame(height: height)
            } else {
                Spacer(minLength: 0)
            }

            Text("剩余 \(Int(remainingPercent.rounded()))%")
                .font(AnimalFont.emphasis(12))
                .foregroundStyle(ink.body)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 58, alignment: .trailing)
        }
        .animation(AnimalMotion.fill, value: remainingPercent)
    }

    @ViewBuilder
    private var track: some View {
        if ink.texturedBar {
            ZStack {
                Capsule()
                    .fill(
                        AnimalPalette.background
                            .shadow(.inner(color: AnimalPalette.trackShadow.opacity(0.08), radius: 4, y: 2))
                    )
                Canvas { context, size in
                    let large = AnimalPalette.dot.opacity(0.15)
                    let small = AnimalPalette.dot.opacity(0.1)
                    context.fill(dotPath(spacing: 28, radius: 1.5, offset: 0, size: size), with: .color(large))
                    context.fill(dotPath(spacing: 14, radius: 1, offset: 7, size: size), with: .color(small))
                }
                .clipShape(Capsule())
            }
        } else {
            Capsule().fill(ink.barTrack)
        }
    }

    private func dotPath(spacing: CGFloat, radius: CGFloat, offset: CGFloat, size: CGSize) -> Path {
        var path = Path()
        var y = offset
        while y < size.height + spacing {
            var x = offset
            while x < size.width + spacing {
                path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                x += spacing
            }
            y += spacing
        }
        return path
    }

    private func fill(width: CGFloat) -> some View {
        Capsule()
            .fill(ink.barFill ?? AnimalPalette.usageColor(usedPercent: 100 - remainingPercent))
            .frame(width: max(0, width))
            .widgetAccentable()
    }
}

/// 对应设计系统的 Tag：小尺寸胶囊
public struct AnimalTag: View {
    @Environment(\.widgetInk) private var ink

    public let text: String
    public var tinted: Bool

    public init(text: String, tinted: Bool = false) {
        self.text = text
        self.tinted = tinted
    }

    public var body: some View {
        Text(text)
            .font(AnimalFont.emphasis(12))
            .foregroundStyle(tinted ? ink.tagText : ink.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(tinted ? ink.tagFill : ink.cardFill)
            .overlay(Capsule().stroke(tinted ? ink.tagBorder : ink.disabled, lineWidth: 1.5))
            .clipShape(Capsule())
            .widgetAccentable(tinted)
    }
}

/// 对应设计系统的 Title，燕尾飘带
public struct RibbonTitle: View {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    private let front = AnimalPalette.primary
    private let back = AnimalPalette.primaryActive
    private let fold = Color(hex: 0x0B6E64)

    public var body: some View {
        Text(text)
            .font(AnimalFont.ribbon(14))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(alignment: .center) {
                ZStack {
                    SwallowTail()
                        .fill(back)
                        .frame(width: 26, height: 22)
                        .offset(x: -46, y: 5)
                    SwallowTail(mirrored: true)
                        .fill(back)
                        .frame(width: 26, height: 22)
                        .offset(x: 46, y: 5)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(front)
                        .rotation3DEffect(.degrees(3), axis: (x: 1, y: 0, z: 0), perspective: 1 / 11.5)
                }
            }
            .overlay(alignment: .bottomLeading) {
                FoldTriangle()
                    .fill(fold)
                    .frame(width: 12, height: 6)
            }
            .overlay(alignment: .bottomTrailing) {
                FoldTriangle(mirrored: true)
                    .fill(fold)
                    .frame(width: 12, height: 6)
            }
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

/// 飘带两侧的燕尾
public struct SwallowTail: Shape {
    public var mirrored: Bool

    public init(mirrored: Bool = false) {
        self.mirrored = mirrored
    }

    public func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = mirrored
            ? [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX - rect.width * 0.3, y: rect.midY),
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY)
            ]
            : [
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.minX + rect.width * 0.3, y: rect.midY),
                CGPoint(x: rect.minX, y: rect.minY)
            ]
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

/// 飘带下方的折角阴影
public struct FoldTriangle: Shape {
    public var mirrored: Bool

    public init(mirrored: Bool = false) {
        self.mirrored = mirrored
    }

    public func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = mirrored
            ? [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY)
            ]
            : [
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.maxY)
            ]
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}
