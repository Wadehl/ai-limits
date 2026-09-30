import Foundation

public struct GrokLimitsProvider: Sendable {
    private static let weeklyWindowMinutes = 10_080
    private static let monthlyWindowMinutes = 43_200
    private static let defaultProxyBase = "https://cli-chat-proxy.grok.com/v1"
    private static let preferredIssuer = "https://auth.x.ai"
    private static let tokenSkew: TimeInterval = 5 * 60

    public init() {}

    private var grokHome: URL {
        LocalPaths.override("GROK_HOME", fallback: LocalPaths.directory(".grok"))
    }

    private var proxyBase: String {
        guard let configured = ProcessInfo.processInfo.environment["GROK_CLI_CHAT_PROXY_BASE_URL"],
              !configured.isEmpty else {
            return Self.defaultProxyBase
        }
        return configured.hasSuffix("/") ? String(configured.dropLast()) : configured
    }

    private struct Session {
        let accessToken: String
        let userId: String?
        let email: String?
        let expiresAt: Date?
    }

    public func fetch() async throws -> ProviderLimits {
        guard let session = try readSession() else {
            return ProviderLimits(
                provider: .grok,
                status: .unavailable,
                error: "本机没有 Grok 的登录凭据，先运行 grok 完成登录",
                updatedAt: Date()
            )
        }
        if let expiresAt = session.expiresAt, expiresAt.timeIntervalSinceNow <= Self.tokenSkew {
            return ProviderLimits(
                provider: .grok,
                status: .error,
                error: "Grok 的登录已经过期，运行一次 grok 让它自行刷新凭据",
                updatedAt: Date()
            )
        }

        let creditsURL = URL(string: "\(proxyBase)/billing?format=credits")!
        let payload = try await HTTP.get(creditsURL, headers: headers(session))
        guard (200..<300).contains(payload.status) else {
            return ProviderLimits(
                provider: .grok,
                status: .error,
                error: "Grok 额度接口返回 HTTP \(payload.status)",
                updatedAt: Date()
            )
        }
        guard let root = try payload.json() as? [String: Any] else {
            throw LimitsError.responseMalformed(creditsURL.absoluteString)
        }
        guard let config = billingConfig(root) else {
            return ProviderLimits(
                provider: .grok,
                status: .unavailable,
                error: "Grok 的账单响应里没有额度信息",
                updatedAt: Date()
            )
        }

        // 账单里已经按产品拆分了每周用量时，就直接展示拆分结果，避免和汇总数字重复
        let products = productBuckets(config)
        let weekly = products.isEmpty ? weeklyWindow(config) : nil
        var monthly = monthlyWindow(config)
        if weekly == nil, monthly == nil {
            let fallbackURL = URL(string: "\(proxyBase)/billing")!
            let fallbackPayload = try await HTTP.get(fallbackURL, headers: headers(session))
            guard (200..<300).contains(fallbackPayload.status) else {
                return ProviderLimits(
                    provider: .grok,
                    status: .error,
                    error: "Grok 额度接口返回 HTTP \(fallbackPayload.status)",
                    updatedAt: Date()
                )
            }
            guard let fallbackRoot = try fallbackPayload.json() as? [String: Any] else {
                throw LimitsError.responseMalformed(fallbackURL.absoluteString)
            }
            monthly = monthlyWindow(billingConfig(fallbackRoot) ?? fallbackRoot)
        }

        return ProviderLimits(
            provider: .grok,
            weekly: weekly,
            monthly: monthly,
            buckets: products,
            planType: nonEmptyString(config["subscriptionTier"]),
            accountLabel: session.email ?? session.userId,
            status: .ok,
            updatedAt: Date()
        )
    }

    private func headers(_ session: Session) -> [String: String] {
        var headers = [
            "Authorization": "Bearer \(session.accessToken)",
            "X-XAI-Token-Auth": "xai-grok-cli",
            "Accept": "application/json"
        ]
        if let userId = session.userId {
            headers["x-userid"] = userId
        }
        return headers
    }

    /// 账单响应可能把字段放在 config 里，也可能直接平铺在根节点
    private func billingConfig(_ root: [String: Any]) -> [String: Any]? {
        if let config = root["config"] as? [String: Any] {
            return config
        }
        let flatKeys = [
            "creditUsagePercent", "currentPeriod", "billingPeriodStart", "billingPeriodEnd",
            "subscriptionTier", "monthlyLimit", "used", "onDemandCap", "onDemandUsed", "prepaidBalance"
        ]
        return flatKeys.contains { root[$0] != nil } ? root : nil
    }

    private func periodEnd(_ config: [String: Any]) -> Date? {
        let period = config["currentPeriod"] as? [String: Any]
        return parseResetDate(period?["end"]) ?? parseResetDate(config["billingPeriodEnd"])
    }

    private func weeklyWindow(_ config: [String: Any]) -> RateLimitWindow? {
        guard let percent = reportedWeeklyPercent(config) else { return nil }
        return makeWindow(usedPercent: percent, windowMinutes: Self.weeklyWindowMinutes, resetsAt: periodEnd(config))
    }

    private func reportedWeeklyPercent(_ config: [String: Any]) -> Double? {
        if let percent = finiteNumber(config["creditUsagePercent"]) {
            return percent
        }
        if config["creditUsagePercent"] != nil {
            return nil
        }
        // 没有给出百分比时，只有在账单周期本身是每周周期、并且没有任何金额字段被上报的情况下，
        // 才能断定本周确实没有消耗
        if reportsUsageAmount(config) || monthlyWindow(config) != nil {
            return nil
        }
        return confirmedWeeklyPeriod(config) ? 0 : nil
    }

    private func confirmedWeeklyPeriod(_ config: [String: Any]) -> Bool {
        guard let period = config["currentPeriod"] as? [String: Any],
              nonEmptyString(period["type"]) == "USAGE_PERIOD_TYPE_WEEKLY" else {
            return false
        }
        let start = parseResetDate(period["start"])
        let end = parseResetDate(period["end"])
        let billingStart = parseResetDate(config["billingPeriodStart"])
        let billingEnd = parseResetDate(config["billingPeriodEnd"])
        return start != nil && start == billingStart && end != nil && end == billingEnd
    }

    private func reportsUsageAmount(_ config: [String: Any]) -> Bool {
        amountKeys.contains { parseAmount(config[$0]) != nil }
    }

    private var amountKeys: [String] {
        ["onDemandCap", "onDemandUsed", "prepaidBalance", "monthlyLimit", "used"]
    }

    private func parseAmount(_ value: Any?) -> Double? {
        if let number = finiteNumber(value) {
            return number
        }
        guard let container = value as? [String: Any] else { return nil }
        return finiteNumber(container["val"])
    }

    private func monthlyWindow(_ config: [String: Any]) -> RateLimitWindow? {
        guard let limit = parseAmount(config["monthlyLimit"]),
              let used = parseAmount(config["used"]),
              limit > 0 else {
            return nil
        }
        return makeWindow(
            usedPercent: (used / limit) * 100,
            windowMinutes: Self.monthlyWindowMinutes,
            resetsAt: periodEnd(config)
        )
    }

    /// 账单响应里按产品划分的用量，例如 GrokBuild
    private func productBuckets(_ config: [String: Any]) -> [RateLimitBucket] {
        guard let products = config["productUsage"] as? [[String: Any]] else { return [] }
        return products.compactMap { product in
            guard let name = nonEmptyString(product["product"]),
                  let percent = finiteNumber(product["usagePercent"]) else {
                return nil
            }
            return RateLimitBucket(
                name: "\(name) · 7 天",
                window: makeWindow(
                    usedPercent: percent,
                    windowMinutes: Self.weeklyWindowMinutes,
                    resetsAt: periodEnd(config)
                )
            )
        }
    }

    /// 优先使用默认签发方的登录，其他签发方的记录只作为兼容回退
    private func readSession() throws -> Session? {
        let authFile = grokHome.appending(path: "auth.json")
        guard let raw = try JSONFile.readIfPresent(at: authFile) else { return nil }
        guard let root = raw as? [String: Any] else {
            throw LimitsError.credentialsMalformed("Grok")
        }

        var preferredExpired: Session?
        var fallback: Session?
        var preferredKeySeen = false
        for (key, value) in root {
            let isPreferred = key == Self.preferredIssuer || key.hasPrefix("\(Self.preferredIssuer)::")
            preferredKeySeen = preferredKeySeen || isPreferred
            guard let entry = value as? [String: Any],
                  let accessToken = nonEmptyString(entry["key"]) else {
                continue
            }
            let session = Session(
                accessToken: accessToken,
                userId: nonEmptyString(entry["user_id"]),
                email: nonEmptyString(entry["email"]),
                expiresAt: parseResetDate(entry["expires_at"])
            )
            if isPreferred {
                if isFresh(session) { return session }
                if preferredExpired == nil { preferredExpired = session }
                continue
            }
            if fallback == nil { fallback = session }
        }
        if let preferredExpired { return preferredExpired }
        return preferredKeySeen ? nil : fallback
    }

    private func isFresh(_ session: Session) -> Bool {
        guard let expiresAt = session.expiresAt else { return true }
        return expiresAt.timeIntervalSinceNow > Self.tokenSkew
    }
}
