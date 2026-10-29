import Foundation
import Testing
@testable import AiLimitsCore

@Suite("显示设置")
struct DisplaySettingsTests {
    @Test("默认展示全部进度条")
    func showsEverythingByDefault() {
        let settings = DisplaySettings()
        for provider in ProviderIdentifier.allCases {
            #expect(settings.showsProgressBar(for: provider))
        }
    }

    @Test("关掉一个账号的进度条不影响其他账号")
    func hidesOneProvider() {
        var settings = DisplaySettings()
        settings.setShowsProgressBar(false, for: .claude)
        #expect(!settings.showsProgressBar(for: .claude))
        #expect(settings.showsProgressBar(for: .codex))
        #expect(settings.showsProgressBar(for: .cursor))
        #expect(settings.showsProgressBar(for: .grok))
    }

    @Test("重新打开之后恢复展示")
    func showsAgain() {
        var settings = DisplaySettings()
        settings.setShowsProgressBar(false, for: .grok)
        settings.setShowsProgressBar(true, for: .grok)
        #expect(settings.showsProgressBar(for: .grok))
        #expect(settings.hiddenProgressBarProviders.isEmpty)
    }
}
