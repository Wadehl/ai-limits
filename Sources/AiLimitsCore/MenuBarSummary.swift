import Foundation

/// 菜单栏上展示的那一份额度：某个账号里剩余百分比最高的窗口
public struct MenuBarSummary: Sendable, Equatable {
    public let provider: ProviderIdentifier
    public let remainingPercent: Double

    public init(provider: ProviderIdentifier, remainingPercent: Double) {
        self.provider = provider
        self.remainingPercent = remainingPercent
    }
}

public extension Array where Element == ProviderLimits {
    /// 每个账号各取自己被关掉之外剩余最多的窗口，按账号的展示顺序排列；菜单栏轮流展示这几份
    func menuBarSummaries(using settings: DisplaySettings = DisplaySettings()) -> [MenuBarSummary] {
        compactMap { limits in
            guard limits.status == .ok else { return nil }
            let best = settings.visibleWindows(of: limits).map(\.window.remainingPercent).max()
            guard let best else { return nil }
            return MenuBarSummary(provider: limits.provider, remainingPercent: best)
        }
    }
}
