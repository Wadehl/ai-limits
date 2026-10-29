import Foundation
import Testing
@testable import AiLimitsCore

@Suite("显示设置")
struct DisplaySettingsTests {
    @Test("默认全部展示")
    func showsEverythingByDefault() {
        let settings = DisplaySettings()
        for provider in ProviderIdentifier.allCases {
            #expect(settings.isVisible(provider))
            #expect(settings.isWindowVisible(LimitWindowKey.session, for: provider))
        }
        #expect(settings.applying(to: [claude, cursor]).map(\.provider) == [.claude, .cursor])
    }

    @Test("关掉整个账号之后其他账号照常展示")
    func hidesWholeProvider() {
        var settings = DisplaySettings()
        settings.setVisible(false, for: .cursor)
        #expect(!settings.isVisible(.cursor))
        #expect(settings.isVisible(.claude))
        #expect(settings.applying(to: [claude, cursor]).map(\.provider) == [.claude])
    }

    @Test("只关掉某一份额度时账号还在")
    func hidesOneWindow() {
        var settings = DisplaySettings()
        settings.setWindowVisible(false, key: LimitWindowKey.monthly, for: .cursor)
        settings.setWindowVisible(false, key: "GrokBot · 7 天", for: .cursor)
        let visible = settings.applying(to: [cursor])
        #expect(visible.count == 1)
        #expect(visible[0].orderedWindows.map(\.key) == ["Cursor Models", "Other Models"])
        #expect(visible[0].planType == "Enterprise")
    }

    @Test("额度全部关掉之后整张卡片不再出现")
    func hidesProviderWhenAllWindowsHidden() {
        var settings = DisplaySettings()
        for window in cursor.orderedWindows {
            settings.setWindowVisible(false, key: window.key, for: .cursor)
        }
        #expect(settings.applying(to: [cursor]).isEmpty)
    }

    @Test("读取失败的账号没有额度窗口，仍然保留")
    func keepsFailedProvider() {
        let failing = ProviderLimits(
            provider: .cursor,
            status: .error,
            error: "凭据读取失败",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        #expect(DisplaySettings().applying(to: [failing]).map(\.provider) == [.cursor])

        var settings = DisplaySettings()
        settings.setVisible(false, for: .cursor)
        #expect(settings.applying(to: [failing]).isEmpty)
    }

    @Test("重新打开之后恢复展示")
    func showsAgain() {
        var settings = DisplaySettings()
        settings.setVisible(false, for: .grok)
        settings.setVisible(true, for: .grok)
        settings.setWindowVisible(false, key: "GrokBuild · 7 天", for: .grok)
        settings.setWindowVisible(true, key: "GrokBuild · 7 天", for: .grok)
        #expect(settings.hiddenProviders.isEmpty)
        #expect(settings.isWindowVisible("GrokBuild · 7 天", for: .grok))
    }

    @Test("写进 JSON 再读回来是同一份设置")
    func roundTripsThroughJSON() throws {
        var settings = DisplaySettings()
        settings.setVisible(false, for: .codex)
        settings.setWindowVisible(false, key: "Other Models", for: .cursor)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(DisplaySettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test("旧版本的设置文件照常读取")
    func readsOlderFile() throws {
        let data = Data(#"{"hiddenProgressBarProviders":["claude"]}"#.utf8)
        let settings = try JSONDecoder().decode(DisplaySettings.self, from: data)
        #expect(settings == DisplaySettings())
    }

    private var claude: ProviderLimits {
        ProviderLimits(
            provider: .claude,
            session: window(usedPercent: 42),
            status: .ok,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private var cursor: ProviderLimits {
        ProviderLimits(
            provider: .cursor,
            monthly: window(usedPercent: 63),
            buckets: [
                RateLimitBucket(name: "Cursor Models", window: window(usedPercent: 70)),
                RateLimitBucket(name: "Other Models", window: window(usedPercent: 42)),
                RateLimitBucket(name: "GrokBot · 7 天", window: window(usedPercent: 36))
            ],
            planType: "Enterprise",
            status: .ok,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func window(usedPercent: Double) -> RateLimitWindow {
        RateLimitWindow(usedPercent: usedPercent, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
    }
}
