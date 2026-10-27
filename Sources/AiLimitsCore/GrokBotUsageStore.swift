import Foundation

/// Grok Bot 桌面应用显示的订阅用量
public struct GrokBotUsage: Sendable, Equatable {
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(usedPercent: Double, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// Grok Bot 把最新一次的用量状态写在它自己的持久化目录里。
/// 这里只读那一份缓存，不接触它的登录凭据。
public struct GrokBotUsageStore: Sendable {
    private static let defaultDirectory = "Library/Application Support/Grok Bot/sand-client-persistence"

    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(Self.defaultDirectory, isDirectory: true)
    }

    /// 缓存里没有可用的读数时返回 nil
    public func read(now: Date = Date()) throws -> GrokBotUsage? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var candidates: [(readAt: Double, usage: GrokBotUsage)] = []
        for file in files where file.pathExtension == "blob" {
            if let entry = try usageEntry(at: file, now: now) {
                candidates.append(entry)
            }
        }
        return candidates.max { $0.readAt < $1.readAt }?.usage
    }

    private func usageEntry(at file: URL, now: Date) throws -> (readAt: Double, usage: GrokBotUsage)? {
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let value = root["value"] as? [String: Any],
              let reading = value["reading"] as? [String: Any],
              let usage = reading["usage"] as? [String: Any] else {
            return nil
        }
        guard let percent = finiteNumber(usage["percentUsed"]) else {
            throw LimitsError.credentialsMalformed("Grok Bot 用量缓存 \(file.lastPathComponent)")
        }
        guard let resetsAt = parseResetDate(usage["nextResetMs"]), resetsAt > now else {
            return nil
        }
        guard let expiresAt = parseResetDate(value["expiresAtMs"]), expiresAt > now else {
            return nil
        }
        return (
            readAt: parseResetDate(reading["readAtMs"])?.timeIntervalSince1970 ?? 0,
            usage: GrokBotUsage(usedPercent: percent, resetsAt: resetsAt)
        )
    }
}
