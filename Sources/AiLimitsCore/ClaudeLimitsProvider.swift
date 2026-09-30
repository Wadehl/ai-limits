import Foundation

public struct ClaudeLimitsProvider: Sendable {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let keychainService = "Claude Code-credentials"
    private static let sessionWindowMinutes = 300
    private static let weeklyWindowMinutes = 10_080

    public init() {}

    public func fetch() async throws -> ProviderLimits {
        guard let token = try readAccessToken() else {
            return ProviderLimits(
                provider: .claude,
                status: .unavailable,
                error: "本机没有 Claude Code 的登录凭据，先运行 claude 完成登录",
                updatedAt: Date()
            )
        }

        let payload = try await HTTP.get(
            Self.usageURL,
            headers: [
                "Authorization": "Bearer \(token)",
                "anthropic-beta": "oauth-2025-04-20",
                "User-Agent": "claude-code/2.1.0"
            ]
        )
        guard (200..<300).contains(payload.status) else {
            return ProviderLimits(
                provider: .claude,
                status: .error,
                error: "Claude 额度接口返回 HTTP \(payload.status)",
                updatedAt: Date()
            )
        }
        let body: Any
        do {
            body = try payload.json()
        } catch {
            throw LimitsError.responseMalformed(Self.usageURL.absoluteString)
        }
        guard let root = body as? [String: Any] else {
            throw LimitsError.responseMalformed(Self.usageURL.absoluteString)
        }

        return ProviderLimits(
            provider: .claude,
            session: window(root["five_hour"], minutes: Self.sessionWindowMinutes),
            weekly: window(root["seven_day"], minutes: Self.weeklyWindowMinutes),
            buckets: fableBuckets(root),
            status: .ok,
            updatedAt: Date()
        )
    }

    /// 钥匙串优先，其次是配置文件；两者都没有时返回 nil
    private func readAccessToken() throws -> String? {
        let account = NSUserName()
        if let raw = try Keychain.genericPassword(service: Self.keychainService, account: account),
           let token = accessToken(inCredentialsJSON: raw) {
            return token
        }
        let file = LocalPaths.directory(".claude").appending(path: ".credentials.json")
        guard let data = try JSONFile.readIfPresent(at: file) else { return nil }
        guard let root = data as? [String: Any] else {
            throw LimitsError.credentialsMalformed("Claude")
        }
        return accessToken(inCredentials: root)
    }

    private func accessToken(inCredentialsJSON raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return accessToken(inCredentials: root)
    }

    private func accessToken(inCredentials root: [String: Any]) -> String? {
        guard let oauth = root["claudeAiOauth"] as? [String: Any] else { return nil }
        return nonEmptyString(oauth["accessToken"])
    }

    /// 每周额度中按模型划分的部分，例如 Fable
    private func fableBuckets(_ root: [String: Any]) -> [RateLimitBucket] {
        var items: [RateLimitBucket] = []
        for limit in root["limits"] as? [[String: Any]] ?? [] {
            guard nonEmptyString(limit["kind"]) == "weekly_scoped",
                  let percent = finiteNumber(limit["percent"]),
                  let scope = limit["scope"] as? [String: Any],
                  let model = scope["model"] as? [String: Any],
                  let name = nonEmptyString(model["display_name"]) else {
                continue
            }
            items.append(
                RateLimitBucket(
                    name: "\(name) · 7 天",
                    window: makeWindow(
                        usedPercent: percent,
                        windowMinutes: Self.weeklyWindowMinutes,
                        resetsAt: parseResetDate(limit["resets_at"])
                    )
                )
            )
        }
        return items
    }

    private func window(_ raw: Any?, minutes: Int) -> RateLimitWindow? {
        guard let raw = raw as? [String: Any] else { return nil }
        guard let percent = finiteNumber(raw["utilization"]) ?? finiteNumber(raw["used_percentage"]) else {
            return nil
        }
        return makeWindow(usedPercent: percent, windowMinutes: minutes, resetsAt: parseResetDate(raw["resets_at"]))
    }
}
