import Foundation
import SQLite3

public struct CursorLimitsProvider: Sendable {
    private static let dashboardOrigin = "https://cursor.com"
    private static let usageSummaryURL = URL(string: "https://cursor.com/api/usage-summary")!
    private static let monthlyWindowMinutes = 43_200
    private static let keychainService = "cursor-access-token"
    private static let keychainAccount = "cursor-user"

    public init() {}

    private var cursorHome: URL {
        LocalPaths.override("CURSOR_CONFIG_DIR", fallback: LocalPaths.directory(".cursor"))
    }

    private var cliAuthFile: URL {
        cursorHome.appending(path: "auth.json")
    }

    private var cliConfigFile: URL {
        cursorHome.appending(path: "cli-config.json")
    }

    private var desktopDatabase: URL {
        LocalPaths.directory("Library/Application Support/Cursor")
            .appending(path: "User/globalStorage/state.vscdb")
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
            ]
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
        let accountLabel = readIdentityEmail() ?? readDesktopProfile()?.email
        let start = parseCursorDate(root["billingCycleStart"])
        let end = parseCursorDate(root["billingCycleEnd"])
        let windowMinutes = windowMinutes(start: start, end: end)

        if root["isUnlimited"] as? Bool == true {
            return ProviderLimits(
                provider: .cursor,
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

    private struct SessionToken {
        let raw: String
        let subject: String
        let expiresAt: Date?
    }

    private func readToken() throws -> SessionToken? {
        if let raw = try Keychain.genericPassword(service: Self.keychainService, account: Self.keychainAccount),
           let token = parseToken(raw) {
            return token
        }
        if let auth = try JSONFile.readIfPresent(at: cliAuthFile) as? [String: Any],
           let raw = nonEmptyString(auth["accessToken"]),
           let token = parseToken(raw) {
            return token
        }
        if let raw = readDesktopProfile()?.accessToken, let token = parseToken(raw) {
            return token
        }
        return nil
    }

    private func parseToken(_ raw: String) -> SessionToken? {
        let parts = raw.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = nonEmptyString(claims["sub"]) else {
            return nil
        }
        let expiresAt = finiteNumber(claims["exp"]).map { Date(timeIntervalSince1970: $0) }
        return SessionToken(raw: raw, subject: subject, expiresAt: expiresAt)
    }

    private func urlEncoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func readIdentityEmail() -> String? {
        guard let config = try? JSONFile.readIfPresent(at: cliConfigFile) as? [String: Any],
              let authInfo = config["authInfo"] as? [String: Any] else {
            return nil
        }
        return nonEmptyString(authInfo["email"])
    }

    private struct DesktopProfile {
        let accessToken: String?
        let email: String?
    }

    /// Cursor 客户端把登录信息放在 state.vscdb 的 ItemTable 里，只读打开
    private func readDesktopProfile() -> DesktopProfile? {
        guard FileManager.default.fileExists(atPath: desktopDatabase.path(percentEncoded: false)) else {
            return nil
        }
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(desktopDatabase.path(percentEncoded: false), &handle, flags, nil) == SQLITE_OK,
              let handle else {
            return nil
        }
        defer { sqlite3_close(handle) }
        sqlite3_busy_timeout(handle, 250)

        let statement = """
        SELECT key, value FROM ItemTable WHERE key IN ('cursorAuth/accessToken', 'cursorAuth/cachedEmail')
        """
        var query: OpaquePointer?
        guard sqlite3_prepare_v2(handle, statement, -1, &query, nil) == SQLITE_OK, let query else {
            return nil
        }
        defer { sqlite3_finalize(query) }

        var values: [String: String] = [:]
        while sqlite3_step(query) == SQLITE_ROW {
            guard let keyText = sqlite3_column_text(query, 0),
                  let valueText = sqlite3_column_text(query, 1) else {
                continue
            }
            values[String(cString: keyText)] = String(cString: valueText)
        }
        return DesktopProfile(
            accessToken: values["cursorAuth/accessToken"],
            email: values["cursorAuth/cachedEmail"]
        )
    }
}
