import Foundation

/// Grok Bot 桌面应用显示的订阅用量
public struct GrokBotUsage: Sendable, Equatable {
    /// Grok Bot 应用里的账号标识，例如 auth0|user_...
    public let accountSlot: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(accountSlot: String, usedPercent: Double, resetsAt: Date?) {
        self.accountSlot = accountSlot
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// Grok Bot 把最新一次的用量状态按账号写在它自己的持久化目录里。
/// 同一个目录里可能有多个账号的缓存，这里只读那一份缓存，不接触它的登录凭据。
public struct GrokBotUsageStore: Sendable {
    private static let defaultDirectory = "Library/Application Support/Grok Bot/sand-client-persistence"
    private static let keyPrefix = "sand.client.slice.account."
    private static let keySuffix = ".weekly-usage.cache"

    private struct Reading {
        let usage: GrokBotUsage
        let readAt: Date
    }

    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(Self.defaultDirectory, isDirectory: true)
    }

    /// 排除给定账号之后最新的一份读数，缓存里没有可用的读数时返回 nil
    public func latest(excluding accountSlots: Set<String> = [], now: Date = Date()) throws -> GrokBotUsage? {
        try readings(now: now)
            .filter { !accountSlots.contains($0.usage.accountSlot) }
            .max(by: { $0.readAt < $1.readAt })?
            .usage
    }

    private func readings(now: Date) throws -> [Reading] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return []
        }

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return try files.compactMap { file -> Reading? in
            guard file.pathExtension == "blob",
                  let key = Self.decodeKey(file.deletingPathExtension().lastPathComponent),
                  let slot = Self.accountSlot(in: key) else {
                return nil
            }
            return try reading(at: file, accountSlot: slot, now: now)
        }
    }

    private func reading(at file: URL, accountSlot: String, now: Date) throws -> Reading? {
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
        return Reading(
            usage: GrokBotUsage(accountSlot: accountSlot, usedPercent: percent, resetsAt: resetsAt),
            readAt: parseResetDate(reading["readAtMs"]) ?? .distantPast
        )
    }

    /// 文件名是存储键的小写 Base32，键的首尾标明这是某个账号的每周用量缓存
    private static func accountSlot(in key: String) -> String? {
        guard key.hasPrefix(keyPrefix), key.hasSuffix(keySuffix) else { return nil }
        let encoded = key.dropFirst(keyPrefix.count).dropLast(keySuffix.count)
        guard !encoded.isEmpty else { return nil }
        return String(encoded).removingPercentEncoding
    }

    private static func decodeKey(_ encoded: String) -> String? {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
        var values: [Character: UInt8] = [:]
        for (offset, character) in alphabet.enumerated() {
            values[character] = UInt8(offset)
        }
        var buffer: UInt32 = 0
        var bits = 0
        var bytes: [UInt8] = []
        for character in encoded.lowercased() {
            guard let value = values[character] else { return nil }
            buffer = (buffer << 5) | UInt32(value)
            bits += 5
            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8((buffer >> UInt32(bits)) & 0xFF))
                buffer &= (UInt32(1) << UInt32(bits)) - 1
            }
        }
        return String(bytes: bytes, encoding: .utf8)
    }
}
