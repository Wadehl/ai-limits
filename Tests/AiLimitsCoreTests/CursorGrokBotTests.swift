import Foundation
import Testing
@testable import AiLimitsCore

private final class CursorStubState: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ((URLRequest) throws -> (Int, String))!

    func respond(_ request: URLRequest) throws -> (Int, String) {
        lock.lock()
        defer { lock.unlock() }
        return try handler(request)
    }

    func set(_ handler: @escaping (URLRequest) throws -> (Int, String)) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
    }
}

private final class CursorStubProtocol: URLProtocol, @unchecked Sendable {
    static let state = CursorStubState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.state.respond(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

@Suite("Cursor 的 GrokBot 额度", .serialized)
struct CursorGrokBotTests {
    private static let usageSummary = """
    {"membershipType":"enterprise",
     "billingCycleStart":"2026-10-07T13:05:36.000Z",
     "billingCycleEnd":"2026-11-07T13:05:36.000Z",
     "individualUsage":{"plan":{"enabled":true,"autoPercentUsed":10,"apiPercentUsed":20,"totalPercentUsed":10}}}
    """

    private func session(_ handler: @escaping (URLRequest) throws -> (Int, String)) -> URLSession {
        CursorStubProtocol.state.set(handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CursorStubProtocol.self]
        return URLSession(configuration: config)
    }

    /// 结构合法、有效期很长的令牌，只用来构造 Bearer 头
    private func token() -> String {
        func encode(_ text: String) -> String {
            Data(text.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let payload = #"{"sub":"auth0|test-user","exp":4102444800}"#
        return "\(encode("{\"alg\":\"none\"}")).\(encode(payload)).signature"
    }

    private func sandUsage(percent: Double, included: Bool = true) -> String {
        """
        {"currentPeriodStart":"2026-10-27T02:15:04.595Z",
         "nextResetTimestampUtc":"2026-11-03T02:15:04.595Z",
         "usagePercent":\(percent),
         "hasAvailableUsage":true,
         "hasNonZeroIncludedLimit":\(included),
         "isTeamSeat":true,
         "grokPlanLabel":"Grok Bot Plan"}
        """
    }

    @Test("Cursor 后台给出的 GrokBot 每周额度进入 Cursor 卡片的额度列表")
    func grokBotBucketAppears() async throws {
        let session = self.session { request in
            switch request.url!.path {
            case "/api/usage-summary":
                return (200, Self.usageSummary)
            case "/aiserver.v1.DashboardService/GetSandUsageStatus":
                #expect(request.httpMethod == "POST")
                #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
                #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
                return (200, self.sandUsage(percent: 42.5))
            default:
                Issue.record("Unexpected request \(request.url!)")
                return (404, "{}")
            }
        }
        defer { session.invalidateAndCancel() }

        let result = try await CursorLimitsProvider(token: token(), urlSession: session).fetch()
        #expect(result.status == .ok)
        let grokBot = try #require(result.buckets.first { $0.name == "GrokBot · 7 天" })
        #expect(grokBot.window.usedPercent == 42.5)
        #expect(grokBot.window.windowMinutes == 10_080)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(grokBot.window.resetsAt == formatter.date(from: "2026-11-03T02:15:04.595Z"))
        #expect(result.buckets.contains { $0.name == "Cursor Models" })
    }

    @Test("没有 GrokBot 额度的账号不显示这一项")
    func grokBotWithoutQuotaSkipped() async throws {
        let session = self.session { request in
            switch request.url!.path {
            case "/api/usage-summary":
                return (200, Self.usageSummary)
            default:
                return (200, self.sandUsage(percent: 0, included: false))
            }
        }
        defer { session.invalidateAndCancel() }

        let result = try await CursorLimitsProvider(token: token(), urlSession: session).fetch()
        #expect(result.status == .ok)
        #expect(!result.buckets.contains { $0.name == "GrokBot · 7 天" })
        #expect(result.buckets.contains { $0.name == "Cursor Models" })
    }

    @Test("没有 GrokBot 权限时只略过这一项", arguments: [401, 403, 404])
    func grokBotRejectedSkipped(status: Int) async throws {
        let session = self.session { request in
            request.url!.path == "/api/usage-summary"
                ? (200, Self.usageSummary)
                : (status, "{}")
        }
        defer { session.invalidateAndCancel() }

        let result = try await CursorLimitsProvider(token: token(), urlSession: session).fetch()
        #expect(result.status == .ok)
        #expect(!result.buckets.contains { $0.name == "GrokBot · 7 天" })
    }

    @Test("GrokBot 额度接口故障时整张卡片报错")
    func grokBotFailureSurfaces() async throws {
        let session = self.session { request in
            request.url!.path == "/api/usage-summary"
                ? (200, Self.usageSummary)
                : (500, "{}")
        }
        defer { session.invalidateAndCancel() }

        await #expect(throws: (any Error).self) {
            try await CursorLimitsProvider(token: token(), urlSession: session).fetch()
        }
    }
}
