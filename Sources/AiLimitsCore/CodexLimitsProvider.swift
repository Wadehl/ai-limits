import Foundation

public struct CodexLimitsProvider: Sendable {
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let sessionWindowMinutes = 300
    private static let weeklyWindowMinutes = 10_080
    /// 接口给出的窗口长度会有一分钟的偏差
    private static let windowToleranceMinutes = 1

    public init() {}

    private var codexHome: URL {
        LocalPaths.override("CODEX_HOME", fallback: LocalPaths.directory(".codex"))
    }

    public func fetch() async throws -> ProviderLimits {
        let authFile = codexHome.appending(path: "auth.json")
        guard let auth = try JSONFile.readIfPresent(at: authFile) as? [String: Any],
              let tokens = auth["tokens"] as? [String: Any],
              let accessToken = nonEmptyString(tokens["access_token"]) else {
            return ProviderLimits(
                provider: .codex,
                status: .unavailable,
                error: "本机没有 Codex 的登录凭据，先运行 codex 完成登录",
                updatedAt: Date()
            )
        }

        var headers = [
            "Authorization": "Bearer \(accessToken)",
            "User-Agent": "codex-cli",
            "OpenAI-Beta": "codex-1",
            "originator": "Codex Desktop"
        ]
        if let accountID = nonEmptyString(tokens["account_id"]) {
            headers["ChatGPT-Account-Id"] = accountID
        }

        let payload = try await HTTP.get(Self.usageURL, headers: headers)
        guard (200..<300).contains(payload.status) else {
            return ProviderLimits(
                provider: .codex,
                status: .error,
                error: "Codex 额度接口返回 HTTP \(payload.status)",
                updatedAt: Date()
            )
        }
        guard let root = try payload.json() as? [String: Any],
              let planType = nonEmptyString(root["plan_type"]) else {
            throw LimitsError.responseMalformed(Self.usageURL.absoluteString)
        }

        let rateLimit = root["rate_limit"] as? [String: Any]
        let classified = classify(
            primary: snapshot(rateLimit?["primary_window"]),
            secondary: snapshot(rateLimit?["secondary_window"])
        )
        return ProviderLimits(
            provider: .codex,
            session: classified.session.map { mapped($0, windowMinutes: $0.minutes ?? Self.sessionWindowMinutes) },
            weekly: classified.weekly.map { mapped($0, windowMinutes: $0.minutes ?? Self.weeklyWindowMinutes) },
            planType: planType,
            accountLabel: nonEmptyString(root["email"]),
            status: .ok,
            updatedAt: Date()
        )
    }

    private struct WindowSnapshot {
        let usedPercent: Double
        let minutes: Int?
        let resetsAt: Date?
    }

    private func snapshot(_ raw: Any?) -> WindowSnapshot? {
        guard let raw = raw as? [String: Any],
              let usedPercent = finiteNumber(raw["used_percent"]) else {
            return nil
        }
        var minutes: Int?
        if let seconds = finiteNumber(raw["limit_window_seconds"]), seconds > 0 {
            minutes = Int((seconds / 60).rounded(.up))
        }
        let resetsAt = finiteNumber(raw["reset_at"]).map { Date(timeIntervalSince1970: $0) }
        return WindowSnapshot(usedPercent: usedPercent, minutes: minutes, resetsAt: resetsAt)
    }

    /// 按窗口长度判定主窗口与次窗口各自属于哪个额度周期
    private func classify(
        primary: WindowSnapshot?,
        secondary: WindowSnapshot?
    ) -> (session: WindowSnapshot?, weekly: WindowSnapshot?) {
        var session: WindowSnapshot?
        var weekly: WindowSnapshot?
        for candidate in [primary, secondary] {
            guard let candidate else { continue }
            if matches(candidate, minutes: Self.sessionWindowMinutes), session == nil {
                session = candidate
            } else if matches(candidate, minutes: Self.weeklyWindowMinutes), weekly == nil {
                weekly = candidate
            }
        }
        if session == nil, let primary, !matches(primary, minutes: Self.sessionWindowMinutes), !matches(primary, minutes: Self.weeklyWindowMinutes) {
            session = primary
        }
        if weekly == nil, let secondary, !matches(secondary, minutes: Self.sessionWindowMinutes), !matches(secondary, minutes: Self.weeklyWindowMinutes) {
            weekly = secondary
        }
        return (session, weekly)
    }

    private func matches(_ snapshot: WindowSnapshot, minutes: Int) -> Bool {
        guard let value = snapshot.minutes else { return false }
        return abs(value - minutes) <= Self.windowToleranceMinutes
    }

    private func mapped(_ snapshot: WindowSnapshot, windowMinutes: Int) -> RateLimitWindow {
        makeWindow(usedPercent: snapshot.usedPercent, windowMinutes: windowMinutes, resetsAt: snapshot.resetsAt)
    }
}
