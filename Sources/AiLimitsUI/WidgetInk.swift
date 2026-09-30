import SwiftUI
import WidgetKit

/// 小组件内容在不同绘制方式下的用色。
/// 系统在非全彩绘制方式下会把整份内容当作模板：忽略颜色、只保留透明度，
/// 所以这些方式改用同一种颜色的不同透明度拉开层次，颜色交给系统决定。
public struct WidgetInk: Sendable {
    public let title: Color
    public let body: Color
    public let muted: Color
    public let disabled: Color
    public let error: Color

    /// 格子的底色。非全彩下必须带透明度，否则不透明的底色会和上面的文字一起被压成同一个颜色
    public let cardFill: Color

    public let barTrack: Color
    /// 为空表示按用量取状态色
    public let barFill: Color?

    public let tagFill: Color
    public let tagText: Color
    public let tagBorder: Color

    /// 网点纹理与内阴影建立在奶油底色上，只有全彩绘制时才画
    public let texturedBar: Bool
}

public extension WidgetInk {
    /// 全彩绘制：设计系统的奶油配色
    static let fullColor = WidgetInk(
        title: AnimalPalette.textTitle,
        body: AnimalPalette.textBody,
        muted: AnimalPalette.textMuted,
        disabled: AnimalPalette.textDisabled,
        error: AnimalPalette.error,
        cardFill: AnimalPalette.backgroundContent,
        barTrack: AnimalPalette.background,
        barFill: nil,
        tagFill: AnimalPalette.primaryBackground,
        tagText: AnimalPalette.primaryActive,
        tagBorder: AnimalPalette.primary.opacity(0.4),
        texturedBar: true
    )

    /// 单色绘制：系统按透明度重新着色，用白色分出主次
    static let monochrome = WidgetInk(
        title: .white,
        body: Color.white.opacity(0.85),
        muted: Color.white.opacity(0.7),
        disabled: Color.white.opacity(0.5),
        error: .white,
        cardFill: Color.white.opacity(0.18),
        barTrack: Color.white.opacity(0.3),
        barFill: .white,
        tagFill: Color.white.opacity(0.3),
        tagText: .white,
        tagBorder: Color.white.opacity(0.45),
        texturedBar: false
    )

    static func resolve(_ mode: WidgetRenderingMode) -> WidgetInk {
        mode == .fullColor ? .fullColor : .monochrome
    }
}

private struct WidgetInkKey: EnvironmentKey {
    static let defaultValue = WidgetInk.fullColor
}

public extension EnvironmentValues {
    /// 小组件内容的用色，默认是全彩
    var widgetInk: WidgetInk {
        get { self[WidgetInkKey.self] }
        set { self[WidgetInkKey.self] = newValue }
    }
}
