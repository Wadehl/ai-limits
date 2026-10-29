import Foundation
import Testing
@testable import AiLimitsCore

@Suite("菜单栏额度")
struct MenuBarSummaryTests {
    @Test("每个账号取自己剩余最多的窗口")
    func picksBestWindowPerProvider() {
        let providers = [
            makeProvider(.claude, session: 97, weekly: 60),
            makeProvider(.cursor, monthly: 92)
        ]
        #expect(providers.menuBarSummaries() == [
            MenuBarSummary(provider: .claude, remainingPercent: 40),
            MenuBarSummary(provider: .cursor, remainingPercent: 8)
        ])
    }

    @Test("按账号的展示顺序返回")
    func keepsProviderOrder() {
        let providers = [
            makeProvider(.codex, session: 20, weekly: 4),
            makeProvider(.claude, session: 50)
        ]
        #expect(providers.menuBarSummaries() == [
            MenuBarSummary(provider: .codex, remainingPercent: 96),
            MenuBarSummary(provider: .claude, remainingPercent: 50)
        ])
    }

    @Test("读取失败与没有凭据的账号不参与轮播")
    func skipsUnavailableProviders() {
        let providers = [
            makeProvider(.claude, session: 10, status: .error),
            makeProvider(.codex, session: 80, status: .unavailable),
            makeProvider(.grok, session: 30)
        ]
        #expect(providers.menuBarSummaries() == [
            MenuBarSummary(provider: .grok, remainingPercent: 70)
        ])
    }

    @Test("没有可展示的窗口时返回空")
    func emptyWithoutWindows() {
        #expect([ProviderLimits]().menuBarSummaries().isEmpty)
        #expect([makeProvider(.claude, status: .unavailable)].menuBarSummaries().isEmpty)
        #expect([makeProvider(.claude)].menuBarSummaries().isEmpty)
    }

    @Test("关掉的账号与额度窗口不参与轮换")
    func skipsHidden() {
        var settings = DisplaySettings()
        settings.setVisible(false, for: .codex)
        let providers = [
            makeProvider(.claude, session: 97, weekly: 60),
            makeProvider(.codex, session: 20)
        ]
        #expect(providers.menuBarSummaries(using: settings) == [
            MenuBarSummary(provider: .claude, remainingPercent: 40)
        ])

        settings.setWindowVisible(false, key: LimitWindowKey.session, for: .claude)
        #expect(providers.menuBarSummaries(using: settings) == [
            MenuBarSummary(provider: .claude, remainingPercent: 40)
        ])

        settings.setWindowVisible(false, key: LimitWindowKey.weekly, for: .claude)
        #expect(providers.menuBarSummaries(using: settings).isEmpty)
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
