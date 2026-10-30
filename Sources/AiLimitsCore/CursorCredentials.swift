import Foundation
import SQLite3

/// Cursor 的登录凭据与账号标识
struct CursorCredentials: Sendable {
    struct SessionToken: Sendable {
        let raw: String
        let subject: String
        let expiresAt: Date?
    }

    struct DesktopProfile: Sendable {
        let accessToken: String?
        let email: String?
    }

    private static let keychainService = "cursor-access-token"
    private static let keychainAccount = "cursor-user"

    private let cursorHome: URL

    init(cursorHome: URL = LocalPaths.override("CURSOR_CONFIG_DIR", fallback: LocalPaths.directory(".cursor"))) {
        self.cursorHome = cursorHome
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

    /// 依次尝试钥匙串、cursor-agent 的 auth.json 与 Cursor 桌面端
    func session() throws -> SessionToken? {
        if let raw = try Keychain.genericPassword(service: Self.keychainService, account: Self.keychainAccount),
           let token = Self.parseToken(raw) {
            return token
        }
        if let auth = try JSONFile.readIfPresent(at: cliAuthFile) as? [String: Any],
           let raw = nonEmptyString(auth["accessToken"]),
           let token = Self.parseToken(raw) {
            return token
        }
        if let raw = readDesktopProfile()?.accessToken, let token = Self.parseToken(raw) {
            return token
        }
        return nil
    }

    /// 这个 Cursor 登录在 Grok Bot 应用里对应的账号标识，来源逐项尝试，取到哪个算哪个
    func accountIdentifiers() -> Set<String> {
        var identifiers: Set<String> = []
        if let config = try? JSONFile.readIfPresent(at: cliConfigFile) as? [String: Any],
           let authInfo = config["authInfo"] as? [String: Any],
           let authId = nonEmptyString(authInfo["authId"]) {
            identifiers.insert(authId)
        }
        if let raw = try? Keychain.genericPassword(service: Self.keychainService, account: Self.keychainAccount),
           let token = Self.parseToken(raw) {
            identifiers.insert(token.subject)
        }
        if let auth = try? JSONFile.readIfPresent(at: cliAuthFile) as? [String: Any],
           let raw = nonEmptyString(auth["accessToken"]),
           let token = Self.parseToken(raw) {
            identifiers.insert(token.subject)
        }
        if let raw = readDesktopProfile()?.accessToken, let token = Self.parseToken(raw) {
            identifiers.insert(token.subject)
        }
        return identifiers
    }

    func identityEmail() -> String? {
        guard let config = try? JSONFile.readIfPresent(at: cliConfigFile) as? [String: Any],
              let authInfo = config["authInfo"] as? [String: Any] else {
            return nil
        }
        return nonEmptyString(authInfo["email"])
    }

    /// Cursor 客户端把登录信息放在 state.vscdb 的 ItemTable 里，只读打开
    func readDesktopProfile() -> DesktopProfile? {
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

    static func parseToken(_ raw: String) -> SessionToken? {
        let parts = raw.split(separator: ".")
        guard parts.count >= 2 else {
            return nil
        }
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
}
