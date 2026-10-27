import Foundation
import Testing
@testable import AiLimitsCore

// All users of the stub are serialized; the callback itself is protected by a lock.
private final class StubState: @unchecked Sendable {
    let lock = NSLock()
    var handler: ((URLRequest) throws -> (Int, String))?
    func respond(_ request: URLRequest) throws -> (Int, String) {
        lock.lock()
        defer { lock.unlock() }
        return try handler!(request)
    }
    func set(_ handler: @escaping (URLRequest) throws -> (Int, String)) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
    }
}

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    static let state = StubState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.state.respond(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite("启动恢复与 Grok 续期", .serialized)
struct RecoveryTests {
    private func session(_ handler: @escaping (URLRequest) throws -> (Int, String)) -> URLSession {
        StubProtocol.state.set(handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }

    @Test("启动时短暂断网后在同一次刷新中恢复")
    func networkRecovery() async throws {
        var calls = 0
        let session = session { _ in
            calls += 1
            if calls == 1 { throw URLError(.notConnectedToInternet) }
            return (200, "{}")
        }
        defer { session.invalidateAndCancel() }
        let result = try await HTTP.get(URL(string: "https://example.test/usage")!, headers: [:], urlSession: session)
        #expect(result.status == 200)
        #expect(calls == 2)
    }

    @Test("暂时的 503 会重试，401 不盲目重试", arguments: [503, 401])
    func statusRecovery(status: Int) async throws {
        var calls = 0
        let session = session { _ in
            calls += 1
            return (calls == 1 ? status : 200, "{}")
        }
        defer { session.invalidateAndCancel() }
        let result = try await HTTP.get(URL(string: "https://example.test/usage")!, headers: [:], urlSession: session)
        #expect(result.status == (status == 503 ? 200 : 401))
        #expect(calls == (status == 503 ? 2 : 1))
    }

    private func fixture(expired: Bool = true) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let root: [String: Any] = [
            "https://auth.x.ai::test-account": [
                "key": "old-access", "refresh_token": "old-refresh",
                "oidc_issuer": "https://auth.x.ai", "oidc_client_id": "fixture-client",
                "expires_at": expired ? "2000-01-01T00:00:00Z" : "2099-01-01T00:00:00Z",
                "principal_type": "user", "principal_id": "fixture-user", "custom_field": "preserved"
            ],
            "unrelated": ["key": "unrelated-token"]
        ]
        try JSONSerialization.data(withJSONObject: root).write(to: home.appendingPathComponent("auth.json"))
        return home
    }

    /// GrokBot 用量缓存指向测试目录下的空目录，不去读本机桌面应用的数据
    private func provider(home: URL, urlSession: URLSession) -> GrokLimitsProvider {
        GrokLimitsProvider(
            home: home,
            urlSession: urlSession,
            grokBotUsage: GrokBotUsageStore(directory: home.appendingPathComponent("grokbot-usage"))
        )
    }

    @Test("过期令牌自动续期；401 也只续期一次", arguments: [true, false])
    func grokRefresh(expired: Bool) async throws {
        let home = try fixture(expired: expired)
        defer { try? FileManager.default.removeItem(at: home) }
        var exchanges = 0
        let session = session { request in
            switch request.url!.path {
            case "/.well-known/openid-configuration":
                return (200, "{\"issuer\":\"https://auth.x.ai\",\"token_endpoint\":\"https://auth.x.ai/oauth2/token\"}")
            case "/oauth2/token":
                exchanges += 1
                #expect(request.httpMethod == "POST")
                return (200, "{\"access_token\":\"new-access\",\"refresh_token\":\"new-refresh\",\"expires_in\":21600}")
            default:
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access" { return (401, "{}") }
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access")
                return (200, "{\"config\":{\"creditUsagePercent\":31}}")
            }
        }
        defer { session.invalidateAndCancel() }
        let result = try await provider(home: home, urlSession: session).fetch()
        #expect(result.status == .ok)
        #expect(result.weekly?.usedPercent == 31)
        #expect(exchanges == 1)
        let root = try JSONFile.read(at: home.appendingPathComponent("auth.json")) as! [String: [String: Any]]
        let entry = root["https://auth.x.ai::test-account"]!
        #expect(entry["key"] as? String == "new-access")
        #expect(entry["refresh_token"] as? String == "new-refresh")
        #expect(entry["custom_field"] as? String == "preserved")
        #expect(root["unrelated"]?["key"] as? String == "unrelated-token")
        let attributes = try FileManager.default.attributesOfItem(atPath: home.appendingPathComponent("auth.json").path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("续期拒绝或暂时失败不覆盖凭据，也不循环兑换", arguments: [400, 503])
    func failedRefresh(status: Int) async throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent("auth.json")
        let before = try Data(contentsOf: file)
        var exchanges = 0
        let session = session { request in
            if request.url!.path.contains("openid-configuration") {
                return (200, "{\"issuer\":\"https://auth.x.ai\",\"token_endpoint\":\"https://auth.x.ai/oauth2/token\"}")
            }
            exchanges += 1
            return (status, status == 400 ? "{\"error\":\"invalid_grant\"}" : "temporary outage")
        }
        defer { session.invalidateAndCancel() }
        do {
            _ = try await provider(home: home, urlSession: session).fetch()
            Issue.record("Expected refresh failure")
        } catch {
            let message = String(describing: error)
            #expect(message.contains(status == 400 ? "重新授权" : "稍后会重试"))
            #expect(!message.contains("old-refresh"))
        }
        #expect(exchanges == 1)
        #expect(try Data(contentsOf: file) == before)
    }

    @Test("并发取数共用 CLI 凭据锁，只兑换一次；服务不轮换时保留 refresh token")
    func concurrentRefresh() async throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        var exchanges = 0
        let session = session { request in
            switch request.url!.path {
            case "/.well-known/openid-configuration":
                return (200, "{\"issuer\":\"https://auth.x.ai\",\"token_endpoint\":\"https://auth.x.ai/oauth2/token\"}")
            case "/oauth2/token":
                exchanges += 1
                // Hold the real flock long enough for the second caller to queue.
                Thread.sleep(forTimeInterval: 0.15)
                return (200, "{\"access_token\":\"new-access\",\"expires_in\":21600}")
            default:
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access")
                return (200, "{\"config\":{\"productUsage\":[{\"product\":\"GrokBuild\",\"usagePercent\":31}]}}")
            }
        }
        defer { session.invalidateAndCancel() }
        async let first = provider(home: home, urlSession: session).fetch()
        async let second = provider(home: home, urlSession: session).fetch()
        let results = try await [first, second]
        #expect(results.allSatisfy { $0.status == .ok && $0.buckets.count == 1 })
        #expect(exchanges == 1)
        let root = try JSONFile.read(at: home.appendingPathComponent("auth.json")) as! [String: [String: Any]]
        #expect(root["https://auth.x.ai::test-account"]?["refresh_token"] as? String == "old-refresh")
    }

    @Test("不向未验证的续期地址发送凭据")
    func untrustedEndpoint() async throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        var calls = 0
        let session = session { _ in
            calls += 1
            return (200, "{\"issuer\":\"https://auth.x.ai\",\"token_endpoint\":\"https://other.example/token\"}")
        }
        defer { session.invalidateAndCancel() }
        await #expect(throws: (any Error).self) {
            try await provider(home: home, urlSession: session).fetch()
        }
        #expect(calls == 1)
    }

    @Test("持续 503 最多请求三次，取消不重试", arguments: [false, true])
    func boundedRetries(cancelled: Bool) async throws {
        var calls = 0
        let session = session { _ in
            calls += 1
            if cancelled { throw URLError(.cancelled) }
            return (503, "{}")
        }
        defer { session.invalidateAndCancel() }
        do {
            let result = try await HTTP.get(URL(string: "https://example.test/usage")!, headers: [:], urlSession: session)
            #expect(!cancelled)
            #expect(result.status == 503)
        } catch { #expect(cancelled) }
        #expect(calls == (cancelled ? 1 : 3))
    }
}
