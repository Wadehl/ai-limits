import Foundation
import Darwin

struct GrokSession: Sendable {
    let entryKey: String
    let accessToken: String
    let userId: String?
    let email: String?
    let expiresAt: Date?
    let refreshToken: String?
    let issuer: String?
    let clientID: String?
    let principalType: String?
    let principalID: String?

    var isFresh: Bool { expiresAt.map { $0.timeIntervalSinceNow > 300 } ?? true }
}

/// Shares Grok CLI's OIDC credentials and auth.json.lock protocol. A rotated
/// refresh token must be persisted before releasing the lock or querying usage.
struct GrokAuthStore: Sendable {
    let home: URL
    let urlSession: URLSession
    private static let issuer = "https://auth.x.ai"
    private var file: URL { home.appendingPathComponent("auth.json") }

    func session(rejectedToken: String? = nil) async throws -> GrokSession? {
        guard let initial = try readSession() else { return nil }
        if initial.isFresh && initial.accessToken != rejectedToken { return initial }

        let lock = try await CredentialFileLock.acquire(in: home)
        defer { lock.release() }
        // Another CLI/app process may have renewed the token while we waited.
        guard let current = try readSession() else { return nil }
        if current.isFresh && current.accessToken != rejectedToken { return current }
        guard let refreshToken = current.refreshToken, let clientID = current.clientID else {
            throw LimitsError.requestFailed("Grok 缺少自动续期凭据，请用 grok login 重新授权一次")
        }
        guard current.issuer == Self.issuer else {
            throw LimitsError.requestFailed("此 Grok 登录来源暂不支持自动续期，请在 Grok 中重新登录")
        }

        let discoveryURL = URL(string: "\(Self.issuer)/.well-known/openid-configuration")!
        let discovery = try await HTTP.get(discoveryURL, headers: ["Accept": "application/json"], urlSession: urlSession)
        guard let metadata = try HTTP.requireSuccess(discovery, url: discoveryURL) as? [String: Any],
              metadata["issuer"] as? String == Self.issuer,
              let endpoint = metadata["token_endpoint"] as? String,
              let tokenURL = URL(string: endpoint),
              tokenURL.scheme == "https", tokenURL.host == "auth.x.ai",
              tokenURL.port == nil || tokenURL.port == 443,
              tokenURL.user == nil, tokenURL.password == nil else {
            throw LimitsError.requestFailed("Grok 登录服务返回了无法验证的续期地址")
        }
        var fields = ["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": clientID]
        fields["principal_type"] = current.principalType
        fields["principal_id"] = current.principalID
        let payload = try await HTTP.postForm(tokenURL, fields: fields, urlSession: urlSession)
        guard (200..<300).contains(payload.status) else {
            // Never show the response body: it may contain credentials.
            let code = (try? payload.json() as? [String: Any])?["error"] as? String
            if ["invalid_grant", "invalid_client", "unauthorized_client"].contains(code ?? "") {
                throw LimitsError.requestFailed("Grok 授权已失效，自动续期被拒绝，请用 grok login 重新授权一次")
            }
            throw LimitsError.requestFailed("Grok 自动续期暂时失败（HTTP \(payload.status)），稍后会重试")
        }
        guard let tokens = try payload.json() as? [String: Any],
              let accessToken = nonEmptyString(tokens["access_token"]),
              let lifetime = finiteNumber(tokens["expires_in"]), lifetime.isFinite, lifetime > 0 else {
            throw LimitsError.responseMalformed(tokenURL.absoluteString)
        }

        // Re-read and merge, preserving other accounts and CLI-owned metadata.
        var root = try readRoot()
        guard var entry = root[current.entryKey] as? [String: Any],
              entry["key"] as? String == current.accessToken,
              entry["refresh_token"] as? String == current.refreshToken else {
            throw LimitsError.requestFailed("Grok 凭据已被其他进程更新，稍后会重新读取")
        }
        entry["key"] = accessToken
        entry["refresh_token"] = nonEmptyString(tokens["refresh_token"]) ?? refreshToken
        entry["expires_at"] = ISO8601DateFormatter().string(from: Date().addingTimeInterval(lifetime))
        root[current.entryKey] = entry
        try secureWrite(root)
        return try readSession()
    }

    private func readRoot() throws -> [String: Any] {
        guard let root = try JSONFile.read(at: file) as? [String: Any] else {
            throw LimitsError.credentialsMalformed("Grok")
        }
        return root
    }

    private func readSession() throws -> GrokSession? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let root = try readRoot()
        let preferred = root.keys.filter { $0 == Self.issuer || $0.hasPrefix("\(Self.issuer)::") }.sorted()
        let keys = preferred.isEmpty ? root.keys.sorted() : preferred
        let sessions = keys.compactMap { key -> GrokSession? in
            guard let entry = root[key] as? [String: Any], let token = nonEmptyString(entry["key"]) else { return nil }
            return GrokSession(
                entryKey: key, accessToken: token, userId: nonEmptyString(entry["user_id"]),
                email: nonEmptyString(entry["email"]), expiresAt: parseResetDate(entry["expires_at"]),
                refreshToken: nonEmptyString(entry["refresh_token"]), issuer: nonEmptyString(entry["oidc_issuer"]),
                clientID: nonEmptyString(entry["oidc_client_id"]), principalType: nonEmptyString(entry["principal_type"]),
                principalID: nonEmptyString(entry["principal_id"])
            )
        }
        return sessions.first(where: \.isFresh) ?? sessions.first
    }

    private func secureWrite(_ root: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        let temporary = home.appendingPathComponent(".auth-\(UUID().uuidString).tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw LimitsError.requestFailed("无法保存 Grok 续期凭据") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: temporary)
        }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        guard rename(temporary.path, file.path) == 0 else {
            throw LimitsError.requestFailed("无法替换 Grok 续期凭据")
        }
    }
}

private final class CredentialFileLock: Sendable {
    private let handle: FileHandle
    private init(fd: Int32) { handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true) }

    static func acquire(in home: URL) async throws -> CredentialFileLock {
        let path = home.appendingPathComponent("auth.json.lock").path
        let fd = open(path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw LimitsError.requestFailed("无法打开 Grok 凭据锁") }
        let lock = CredentialFileLock(fd: fd)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK, ContinuousClock.now < deadline else {
                throw LimitsError.requestFailed("Grok 正在更新登录凭据，稍后会重试")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        // Compatible with CLI versions that inspect PID:timestamp holder info.
        let stamp = Data("\(getpid()):\(Int(Date().timeIntervalSince1970))".utf8)
        try lock.handle.truncate(atOffset: 0)
        try lock.handle.write(contentsOf: stamp)
        return lock
    }

    func release() {
        // Keep auth.json.lock on disk; removing it would break mutual exclusion.
        _ = flock(handle.fileDescriptor, LOCK_UN)
        try? handle.close()
    }
}
