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
                    planType: "Max",
                    status: .ok,
                    updatedAt: Date()
                ),
                ProviderLimits(
                    provider: .codex,
                    session: RateLimitWindow(usedPercent: 76, windowMinutes: 300, resetsAt: nil, resetDescription: "48 分钟"),
                    weekly: RateLimitWindow(usedPercent: 31, windowMinutes: 10080, resetsAt: nil, resetDescription: "3 天"),
                    planType: "Plus",
                    status: .ok,
                    updatedAt: Date()
                ),
                ProviderLimits(
                    provider: .cursor,
                    monthly: RateLimitWindow(usedPercent: 63, windowMinutes: 43200, resetsAt: nil, resetDescription: "12 天"),
                    buckets: [
                        RateLimitBucket(
                            name: "Cursor Models",
                            window: RateLimitWindow(usedPercent: 70, windowMinutes: 43200, resetsAt: nil, resetDescription: "12 天")
                        ),
                        RateLimitBucket(
                            name: "Other Models",
                            window: RateLimitWindow(usedPercent: 42, windowMinutes: 43200, resetsAt: nil, resetDescription: "12 天")
                        ),
                        RateLimitBucket(
                            name: "GrokBot · 7 天",
                            window: RateLimitWindow(usedPercent: 36, windowMinutes: 10080, resetsAt: nil, resetDescription: "4 天")
                        )
                    ],
                    planType: "Enterprise",
                    status: .ok,
                    updatedAt: Date()
                ),
                ProviderLimits(
                    provider: .grok,
                    buckets: [
                        RateLimitBucket(
                            name: "GrokBuild · 7 天",
                            window: RateLimitWindow(usedPercent: 30, windowMinutes: 10080, resetsAt: nil, resetDescription: "3 天")
                        ),
                        RateLimitBucket(
                            name: "GrokBot · 7 天",
                            window: RateLimitWindow(usedPercent: 12, windowMinutes: 10080, resetsAt: nil, resetDescription: "5 天")
                        )
                    ],
                    planType: "SuperGrok",
                    status: .ok,
                    updatedAt: Date()
                )
            ],
            fetchedAt: Date()
        )
    }
}
