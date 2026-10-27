import WidgetKit
import SwiftUI
import AiLimitsCore
import AiLimitsUI

@main
struct AiLimitsWidgetBundle: WidgetBundle {
    init() {
        AnimalFont.register()
    }

    var body: some Widget {
        AiLimitsWidget()
    }
}

struct AiLimitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AiLimitsWidget", provider: LimitsTimelineProvider()) { entry in
            AiLimitsWidgetView(entry: entry)
        }
        .configurationDisplayName("Agent 额度")
        .description("狸记额度：查看本机 Claude、Codex、Cursor、Grok 的额度剩余")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

/// 从环境里取出系统给的尺寸与绘制方式，交给版面视图
struct AiLimitsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: LimitsEntry

    var body: some View {
        WidgetLayoutView(entry: entry, family: family)
            .containerBackground(for: .widget) {
                background
            }
    }

    /// 调暗之后系统换成自己的玻璃底，这里不能再画不透明的奶油底，否则整块内容会被压成同一个颜色
    @ViewBuilder
    private var background: some View {
        if renderingMode == .fullColor {
            AnimalPalette.background
        } else {
            Color.clear
        }
    }
}
