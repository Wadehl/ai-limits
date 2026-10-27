import Foundation
import Testing
@testable import AiLimitsCore

@Suite("剩余额度")
struct RemainingPercentTests {
    @Test("剩余百分比等于一百减去已用")
    func remainingPercent() {
        let window = RateLimitWindow(usedPercent: 42, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        #expect(window.remainingPercent == 58)
        #expect(RateLimitWindow(usedPercent: 0, windowMinutes: 300, resetsAt: nil, resetDescription: nil).remainingPercent == 100)
        #expect(RateLimitWindow(usedPercent: 100, windowMinutes: 300, resetsAt: nil, resetDescription: nil).remainingPercent == 0)
    }

    @Test("已用超过一百时剩余为零")
    func clampedAtZero() {
        let window = RateLimitWindow(usedPercent: 140, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        #expect(window.remainingPercent == 0)
    }
}
