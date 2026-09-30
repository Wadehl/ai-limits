import Testing
import WidgetKit
import AiLimitsCore
@testable import AiLimitsUI

@Suite("小组件版面")
struct WidgetLayoutTests {
    @Test("单格、双格、四格分别是 1、2、4 份")
    func cellCount() {
        #expect(WidgetLayout.cellCount(for: .systemSmall) == 1)
        #expect(WidgetLayout.cellCount(for: .systemMedium) == 2)
        #expect(WidgetLayout.cellCount(for: .systemLarge) == 4)
    }

    @Test("样例数据下三种尺寸各画出对应份数")
    func visibleCount() {
        #expect(WidgetLayout.visible(.sample, family: .systemSmall).count == 1)
        #expect(WidgetLayout.visible(.sample, family: .systemMedium).count == 2)
        #expect(WidgetLayout.visible(.sample, family: .systemLarge).count == 4)
    }

    @Test("按消耗最高的窗口从高到低排")
    func rankedOrder() {
        let ranked = WidgetLayout.ranked(.sample)
        #expect(ranked.map(\.provider) == [.codex, .cursor, .claude, .grok])
    }

    @Test("本机取不到数据的账号不占格子")
    func unavailableExcluded() {
        let snapshot = RateLimitSnapshot(
            providers: [
                ProviderLimits(provider: .claude, status: .unavailable, updatedAt: Date()),
                ProviderLimits(
                    provider: .grok,
                    session: RateLimitWindow(usedPercent: 10, windowMinutes: 120, resetsAt: nil, resetDescription: nil),
                    status: .ok,
                    updatedAt: Date()
                )
            ],
            fetchedAt: Date()
        )
        #expect(WidgetLayout.ranked(snapshot).map(\.provider) == [.grok])
        #expect(WidgetLayout.visible(snapshot, family: .systemLarge).count == 1)
    }

    @Test("账号不足时排在前面的仍然占格")
    func shortfallKeepsLeader() {
        let snapshot = RateLimitSnapshot(
            providers: [
                ProviderLimits(
                    provider: .claude,
                    weekly: RateLimitWindow(usedPercent: 88, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
                    status: .ok,
                    updatedAt: Date()
                ),
                ProviderLimits(
                    provider: .codex,
                    weekly: RateLimitWindow(usedPercent: 5, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
                    status: .ok,
                    updatedAt: Date()
                )
            ],
            fetchedAt: Date()
        )
        #expect(WidgetLayout.visible(snapshot, family: .systemSmall).map(\.provider) == [.claude])
        #expect(WidgetLayout.visible(snapshot, family: .systemMedium).map(\.provider) == [.claude, .codex])
    }

    @Test("请求失败的账号仍然占格，用来显示错误")
    func errorStaysVisible() {
        let snapshot = RateLimitSnapshot(
            providers: [
                ProviderLimits(provider: .cursor, status: .error, error: "凭据读取失败", updatedAt: Date())
            ],
            fetchedAt: Date()
        )
        #expect(WidgetLayout.visible(snapshot, family: .systemSmall).count == 1)
    }
}
