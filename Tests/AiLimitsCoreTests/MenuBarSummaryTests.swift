import Foundation
import Testing
@testable import AiLimitsCore

@Suite("菜单栏额度")
struct MenuBarSummaryTests {
    @Test("取所有窗口里剩余最高的一个")
    func highestWindowWins() {
        let providers = [
            makeProvider(.claude, session: 97, weekly: 60),
            makeProvider(.cursor, monthly: 92)
        ]
        #expect(providers.highestRemainingSummary() == MenuBarSummary(provider: .claude, remainingPercent: 40))
    }

    @Test("跨账号比较剩余百分比")
    func comparesAcrossProviders() {
        let providers = [
            makeProvider(.claude, session: 95, weekly: 90),
            makeProvider(.codex, session: 20, weekly: 4)
        ]
        #expect(providers.highestRemainingSummary() == MenuBarSummary(provider: .codex, remainingPercent: 96))
    }

    @Test("并列时沿用账号顺序")
    func keepsEarliestOnTie() {
        let providers = [
            makeProvider(.claude, session: 50),
            makeProvider(.grok, session: 50)
        ]
        #expect(providers.highestRemainingSummary() == MenuBarSummary(provider: .claude, remainingPercent: 50))
    }

    @Test("读取失败与没有凭据的账号不参与比较")
    func skipsUnavailableProviders() {
        let providers = [
            makeProvider(.claude, session: 10, status: .error),
            makeProvider(.codex, session: 80, status: .unavailable),
            makeProvider(.grok, session: 30)
        ]
        #expect(providers.highestRemainingSummary() == MenuBarSummary(provider: .grok, remainingPercent: 70))
    }

    @Test("没有可展示的窗口时返回空")
    func emptyWithoutWindows() {
        #expect([ProviderLimits]().highestRemainingSummary() == nil)
        #expect([makeProvider(.claude, status: .unavailable)].highestRemainingSummary() == nil)
    }

    private func makeProvider(
        _ provider: ProviderIdentifier,
        session: Double? = nil,
        weekly: Double? = nil,
        monthly: Double? = nil,
        status: ProviderStatus = .ok
    ) -> ProviderLimits {
        ProviderLimits(
            provider: provider,
            session: session.map { window(usedPercent: $0) },
            weekly: weekly.map { window(usedPercent: $0) },
            monthly: monthly.map { window(usedPercent: $0) },
            status: status,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func window(usedPercent: Double) -> RateLimitWindow {
        RateLimitWindow(usedPercent: usedPercent, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
    }
}
