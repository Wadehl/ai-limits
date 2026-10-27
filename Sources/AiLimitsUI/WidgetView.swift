import SwiftUI
import WidgetKit
import AiLimitsCore

/// 小组件要展示的内容：应用写下的快照、还没写过、或者读取失败
public enum WidgetData: Sendable {
    case ready(RateLimitSnapshot)
    case empty
    case failed(String)
}

public struct LimitsEntry: TimelineEntry {
    public let date: Date
    public let data: WidgetData

    public init(date: Date, data: WidgetData) {
        self.date = date
        self.data = data
    }
}

/// 小组件的版面，单格一份、双格两份、四格四份
public struct WidgetLayoutView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    public let entry: LimitsEntry
    public let family: WidgetFamily

    public init(entry: LimitsEntry, family: WidgetFamily) {
        self.entry = entry
        self.family = family
    }

    /// 系统调暗小组件时不再使用全彩，内容改用单色绘制
    private var ink: WidgetInk {
        WidgetInk.resolve(renderingMode)
    }

    public var body: some View {
        content
            .padding(14)
            .environment(\.widgetInk, ink)
    }

    @ViewBuilder
    private var content: some View {
        switch entry.data {
        case .ready(let snapshot):
            ready(snapshot)
        case .empty:
            message("打开狸记额度\n读取本机额度")
        case .failed(let text):
            message(text)
        }
    }

    @ViewBuilder
    private func ready(_ snapshot: RateLimitSnapshot) -> some View {
        let providers = WidgetLayout.visible(snapshot, family: family)
        if providers.isEmpty {
            message("本机没有检测到已登录的 Agent")
        } else if family == .systemLarge {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    title
                    Spacer(minLength: 0)
                    Text(updatedText(snapshot.fetchedAt))
                        .font(AnimalFont.body(10))
                        .foregroundStyle(ink.muted)
                }
                grid(providers)
            }
        } else {
            grid(providers)
        }
    }

    @ViewBuilder
    private func grid(_ providers: [ProviderLimits]) -> some View {
        switch family {
        case .systemSmall:
            cell(providers[0], showsReset: true)
        case .systemMedium:
            HStack(spacing: 10) {
                ForEach(providers, id: \.provider) { cell($0, showsReset: false) }
                if providers.count < 2 { Color.clear }
            }
        default:
            VStack(spacing: 10) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(rowProviders(providers, row: row), id: \.provider) { cell($0, showsReset: true) }
                        if rowProviders(providers, row: row).count < 2 { Color.clear }
                    }
                }
            }
        }
    }

    private func cell(_ limits: ProviderLimits, showsReset: Bool) -> some View {
        WidgetProviderCell(limits: limits, showsReset: showsReset)
    }

    private func rowProviders(_ providers: [ProviderLimits], row: Int) -> [ProviderLimits] {
        Array(providers.dropFirst(row * 2).prefix(2))
    }

    /// 飘带是不透明的色块，单色绘制下会和上面的文字压成同一个颜色，改用纯文字
    @ViewBuilder
    private var title: some View {
        if renderingMode == .fullColor {
            RibbonTitle(text: "Agent 额度")
        } else {
            Text("Agent 额度")
                .font(AnimalFont.ribbon(14))
                .foregroundStyle(ink.title)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(AnimalFont.body(12))
            .foregroundStyle(ink.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func updatedText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return "更新于 \(formatter.string(from: date))"
    }
}

private struct WidgetProviderCell: View {
    @Environment(\.widgetInk) private var ink

    let limits: ProviderLimits
    let showsReset: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            if limits.status == .ok {
                ForEach(Array(limits.orderedWindows.prefix(2)), id: \.name) { item in
                    windowBlock(name: item.name, window: item.window)
                }
            } else if let error = limits.error {
                Text(error)
                    .font(AnimalFont.body(10))
                    .foregroundStyle(ink.error)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ink.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(limits.provider.displayName)
                .font(AnimalFont.heading(14))
                .foregroundStyle(ink.title)
                .lineLimit(1)
            if let plan = limits.planType {
                AnimalTag(text: plan, tinted: true)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
    }

    private func windowBlock(name: String, window: RateLimitWindow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(name)
                    .font(AnimalFont.body(11))
                    .foregroundStyle(ink.muted)
                Spacer(minLength: 0)
                if showsReset, let reset = window.resetDescription {
                    Text("重置于 \(reset)")
                        .font(AnimalFont.body(10))
                        .foregroundStyle(ink.disabled)
                        .lineLimit(1)
                }
            }
            LimitBar(remainingPercent: window.remainingPercent, height: 8)
        }
    }
}
