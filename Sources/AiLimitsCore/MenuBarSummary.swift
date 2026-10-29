import Foundation

/// 菜单栏上展示的那一份额度：所有账号、所有窗口里剩余百分比最高的一个
public struct MenuBarSummary: Sendable, Equatable {
    public let provider: ProviderIdentifier
    public let remainingPercent: Double

    public init(provider: ProviderIdentifier, remainingPercent: Double) {
        self.provider = provider
        self.remainingPercent = remainingPercent
    }
}

public extension Array where Element == ProviderLimits {
    /// 取剩余百分比最高的窗口；并列时沿用账号与窗口的展示顺序
    func highestRemainingSummary() -> MenuBarSummary? {
        var best: MenuBarSummary?
        for limits in self where limits.status == .ok {
            for item in limits.orderedWindows {
                let candidate = MenuBarSummary(provider: limits.provider, remainingPercent: item.window.remainingPercent)
                if best.map({ candidate.remainingPercent > $0.remainingPercent }) ?? true {
                    best = candidate
                }
            }
        }
        return best
    }
}
