import Foundation

public struct CursorLimitsProvider: Sendable {
    private static let dashboardOrigin = "https://cursor.com"
    private static let usageSummaryURL = URL(string: "https://cursor.com/api/usage-summary")!
    private static let grokBotUsageURL = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus"
    )!
    private static let monthlyWindowMinutes = 43_200
    private static let grokBotWindowMinutes = 10_080

    private let urlSession: URLSession
    private let tokenOverride: String?
    private let credentials: CursorCredentials

    public init() {
        urlSession = .shared
        tokenOverride = nil
        credentials = CursorCredentials()
    }

    init(token: String, urlSession: URLSession) {
        self.urlSession = urlSession
        tokenOverride = token
        credentials = CursorCredentials()
    }

    public func fetch() async throws -> ProviderLimits {
        guard let token = try readToken() else {
            return unavailable("本机没有 Cursor 的登录凭据，先用 Cursor 客户端或者 cursor-agent login 登录")
        }
        if let expiresAt = token.expiresAt, expiresAt <= Date() {
            return ProviderLimits(
                provider: .cursor,
                status: .error,
                error: "Cursor 的登录已经过期，重新运行 cursor-agent login",
                updatedAt: Date()
            )
        }

        let cookie = "WorkosCursorSessionToken=\(urlEncoded("\(token.subject)::\(token.raw)"))"
        let payload = try await HTTP.get(
            Self.usageSummaryURL,
            headers: [
                "Cookie": cookie,
                "Accept": "application/json",
                "Origin": Self.dashboardOrigin,
                "Referer": "\(Self.dashboardOrigin)/dashboard"
            ],
            urlSession: urlSession
        )
        switch payload.status {
        case 200..<300:
            break
        case 401, 403, 300..<400:
            return ProviderLimits(
                provider: .cursor,
                status: .error,
                error: "Cursor 的登录已经失效，重新运行 cursor-agent login",
                updatedAt: Date()
            )
        default:
            return ProviderLimits(
                provider: .cursor,
                status: .error,
                error: "Cursor 额度接口返回 HTTP \(payload.status)",
                updatedAt: Date()
            )
        }

        guard let root = try payload.json() as? [String: Any] else {
            throw LimitsError.responseMalformed(Self.usageSummaryURL.absoluteString)
        }

        let planType = nonEmptyString(root["membershipType"])
        let accountLabel = credentials.identityEmail() ?? credentials.readDesktopProfile()?.email
        let start = parseCursorDate(root["billingCycleStart"])
        let end = parseCursorDate(root["billingCycleEnd"])
        let windowMinutes = windowMinutes(start: start, end: end)

        if root["isUnlimited"] as? Bool == true {
            let grokBot = try await grokBotBucket(token: token)
            return ProviderLimits(
                provider: .cursor,
                buckets: grokBot.map { [$0] } ?? [],
                planType: planType,
                accountLabel: accountLabel,
                status: .ok,
                updatedAt: Date()
            )
        }

        let individual = root["individualUsage"] as? [String: Any]
        let plan = individual?["plan"] as? [String: Any]
        let planEnabled = plan?["enabled"] as? Bool != false

        func window(_ percent: Double) -> RateLimitWindow {
            makeWindow(usedPercent: percent, windowMinutes: windowMinutes, resetsAt: end)
        }

        var buckets: [RateLimitBucket] = []
        if planEnabled, let percent = finiteNumber(plan?["autoPercentUsed"]) {
            buckets.append(RateLimitBucket(name: "Cursor Models", window: window(percent)))
        }
        if planEnabled, let percent = finiteNumber(plan?["apiPercentUsed"]) {
            buckets.append(RateLimitBucket(name: "Other Models", window: window(percent)))
        }
        let onDemand = individual?["onDemand"] as? [String: Any]
        if onDemand?["enabled"] as? Bool == true,
           let percent = poolPercent(onDemand, fallbackKey: "totalPercentUsed") {
            buckets.append(RateLimitBucket(name: "On-demand", window: window(percent)))
        }
        if let grokBot = try await grokBotBucket(token: token) {
            buckets.append(grokBot)
        }

        let planPercent = planEnabled ? poolPercent(plan, fallbackKey: "totalPercentUsed") : nil
        return ProviderLimits(
            provider: .cursor,
            monthly: planPercent.map { window($0) },
            buckets: buckets,
            planType: planType,
            accountLabel: accountLabel,
            status: .ok,
            updatedAt: Date()
        )
    }

    private func unavailable(_ message: String) -> ProviderLimits {
        ProviderLimits(provider: .cursor, status: .unavailable, error: message, updatedAt: Date())
    }

    /// 已用百分比：接口给出的 totalPercentUsed 已经把赠送额度算进总量，
    /// 而 used/limit 两者都是套餐内含额度，因此优先采用接口给出的百分比
    private func poolPercent(_ pool: [String: Any]?, fallbackKey: String) -> Double? {
        if let percent = finiteNumber(pool?[fallbackKey]) {
            return percent
        }
        guard let used = finiteNumber(pool?["used"]), let limit = finiteNumber(pool?["limit"]), limit > 0 else {
            return nil
        }
        return (used / limit) * 100
    }

    /// Cursor 的账号后台同时给出 GrokBot 的每周额度，和 GrokBuild 的账单是两套数字。
    /// hasNonZeroIncludedLimit 为 false 表示这个账号没有可用的 GrokBot 额度。
    private func grokBotBucket(token: CursorCredentials.SessionToken) async throws -> RateLimitBucket? {
        let payload = try await HTTP.postJSON(
            Self.grokBotUsageURL,
            body: Data("{}".utf8),
            headers: ["Authorization": "Bearer \(token.raw)", "Accept": "application/json"],
            urlSession: urlSession
        )
        switch payload.status {
        case 200..<300:
            break
        case 401, 403, 404:
            return nil
        default:
            throw LimitsError.responseRejected(Self.grokBotUsageURL.absoluteString, payload.status)
        }
        guard let root = try payload.json() as? [String: Any] else {
            throw LimitsError.responseMalformed(Self.grokBotUsageURL.absoluteString)
        }
        guard root["usesPooledEnterpriseAllowance"] as? Bool != true,
              root["hasNonZeroIncludedLimit"] as? Bool == true,
              let percent = finiteNumber(root["usagePercent"]) else {
            return nil
        }
        return RateLimitBucket(
            name: "GrokBot · 7 天",
            window: makeWindow(
                usedPercent: percent,
                windowMinutes: Self.grokBotWindowMinutes,
                resetsAt: parseCursorDate(root["nextResetTimestampUtc"])
            )
        )
    }

    private func windowMinutes(start: Date?, end: Date?) -> Int {
        guard let start, let end, end > start else { return Self.monthlyWindowMinutes }
        return max(1, Int(((end.timeIntervalSince(start)) / 60).rounded()))
    }

    /// Cursor 的时间字段同时存在秒级与毫秒级时间戳
    private func parseCursorDate(_ value: Any?) -> Date? {
        if let number = finiteNumber(value) {
            return Date(timeIntervalSince1970: number > 1e12 ? number / 1000 : number)
        }
        guard let text = nonEmptyString(value) else { return nil }
        if let number = Double(text) {
            return Date(timeIntervalSince1970: number > 1e12 ? number / 1000 : number)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private func readToken() throws -> CursorCredentials.SessionToken? {
        if let tokenOverride, let token = CursorCredentials.parseToken(tokenOverride) {
            return token
        }
        return try credentials.session()
    }

    private func urlEncoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
