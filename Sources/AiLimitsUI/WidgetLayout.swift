import WidgetKit
import AiLimitsCore

/// 小组件的版面规则：单格一份、双格两份、四格四份
public enum WidgetLayout {
    public static func cellCount(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: 1
        case .systemMedium: 2
        default: 4
        }
    }

    /// 去掉本机取不到数据的账号、设置里关掉的账号与额度窗口，再按消耗最高的窗口从高到低排，
    /// 让占用最多的 Agent 排在前面
    public static func ranked(_ snapshot: RateLimitSnapshot, using settings: DisplaySettings = DisplaySettings()) -> [ProviderLimits] {
        settings.applying(to: snapshot.providers)
            .filter { $0.status != .unavailable }
            .sorted { lhs, rhs in
                let left = lhs.orderedWindows.map(\.window.usedPercent).max() ?? -1
                let right = rhs.orderedWindows.map(\.window.usedPercent).max() ?? -1
                if left != right { return left > right }
                return lhs.provider.rawValue < rhs.provider.rawValue
            }
    }

    /// 该尺寸下真正要画的几份额度
    public static func visible(
        _ snapshot: RateLimitSnapshot,
        family: WidgetFamily,
        using settings: DisplaySettings = DisplaySettings()
    ) -> [ProviderLimits] {
        Array(ranked(snapshot, using: settings).prefix(cellCount(for: family)))
    }
}
