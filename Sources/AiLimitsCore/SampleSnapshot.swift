import Foundation

public extension RateLimitSnapshot {
    /// 小组件预览与渲染验证用的样例数据
    static var sample: RateLimitSnapshot {
        RateLimitSnapshot(
            providers: [
                ProviderLimits(
                    provider: .claude,
                    session: RateLimitWindow(usedPercent: 42, windowMinutes: 300, resetsAt: nil, resetDescription: "2 小时"),
                    weekly: RateLimitWindow(usedPercent: 18, windowMinutes: 10080, resetsAt: nil, resetDescription: "5 天"),
                    status: .ok,
                    updatedAt: Date()
                ),
                ProviderLimits(
                    provider: .codex,
                    session: RateLimitWindow(usedPercent: 76, windowMinutes: 300, resetsAt: nil, resetDescription: "48 分钟"),
                    weekly: RateLimitWindow(usedPercent: 31, windowMinutes: 10080, resetsAt: nil, resetDescription: "3 天"),
                    status: .ok,
                    updatedAt: Date()
                ),
                ProviderLimits(
                    provider: .cursor,
                    monthly: RateLimitWindow(usedPercent: 63, windowMinutes: 43200, resetsAt: nil, resetDescription: "12 天"),
                    status: .ok,
                    updatedAt: Date()
                ),
                ProviderLimits(
                    provider: .grok,
                    session: RateLimitWindow(usedPercent: 12, windowMinutes: 120, resetsAt: nil, resetDescription: "1 小时"),
                    status: .ok,
                    updatedAt: Date()
                )
            ],
            fetchedAt: Date()
        )
    }
}
