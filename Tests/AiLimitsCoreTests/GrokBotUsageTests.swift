import Foundation
import Testing
@testable import AiLimitsCore

@Suite("GrokBot 用量")
struct GrokBotUsageTests {
    private let cursorSlot = "auth0|user_cursor"
    private let otherSlot = "auth0|user_other"

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbot-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Grok Bot 把存储键写成小写 Base32 的文件名
    private func fileName(for key: String) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
        var buffer: UInt32 = 0
        var bits = 0
        var encoded = ""
        for byte in key.utf8 {
            buffer = (buffer << 8) | UInt32(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                encoded.append(alphabet[Int((buffer >> UInt32(bits)) & 0x1F)])
            }
            buffer &= (UInt32(1) << UInt32(bits)) - 1
        }
        if bits > 0 {
            encoded.append(alphabet[Int((buffer << UInt32(5 - bits)) & 0x1F)])
        }
        return "\(encoded).blob"
    }

    private func cacheKey(for accountSlot: String) -> String {
        let encodedSlot = accountSlot.addingPercentEncoding(
            withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        ) ?? accountSlot
        return "sand.client.slice.account.\(encodedSlot).weekly-usage.cache"
    }

    @discardableResult
    private func writeBlob(
        for accountSlot: String,
        in directory: URL,
        percent: Double,
        resetsAtMs: Double,
        readAtMs: Double,
        expiresAtMs: Double
    ) throws -> String {
        let object: [String: Any] = [
            "schemaVersion": 2,
            "value": [
                "kind": "present",
                "selectedTeamId": NSNull(),
                "reading": [
                    "usage": [
                        "percentUsed": percent,
                        "nextResetMs": resetsAtMs,
                        "isSandTrial": false,
                        "hasNonZeroIncludedLimit": true,
                        "isTeamSeat": false,
                        "onDemand": NSNull(),
                        "grokPlanLabel": "SuperGrok"
                    ],
                    "readAtMs": readAtMs
                ],
                "expiresAtMs": expiresAtMs
            ]
        ]
        let name = fileName(for: cacheKey(for: accountSlot))
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: directory.appendingPathComponent(name))
        return name
    }

    @Test("读取缓存里的用量、账号与重置时间")
    func freshReading() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        try writeBlob(
            for: cursorSlot,
            in: directory,
            percent: 64.186881,
            resetsAtMs: 1_793_000_000_000,
            readAtMs: 1_792_000_000_000,
            expiresAtMs: 1_792_086_400_000
        )

        let usage = try GrokBotUsageStore(directory: directory).latest(now: now)
        #expect(usage?.accountSlot == cursorSlot)
        #expect(usage?.usedPercent == 64.186881)
        #expect(usage?.resetsAt?.timeIntervalSince1970 == 1_793_000_000)
    }

    @Test("缓存过期后不再返回读数")
    func expiredReadingSkipped() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        try writeBlob(
            for: cursorSlot,
            in: directory,
            percent: 20,
            resetsAtMs: 1_793_000_000_000,
            readAtMs: 1_791_900_000_000,
            expiresAtMs: 1_791_986_400_000
        )

        #expect(try GrokBotUsageStore(directory: directory).latest(now: now) == nil)
    }

    @Test("周期已经结束的读数不再返回")
    func passedResetSkipped() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        try writeBlob(
            for: cursorSlot,
            in: directory,
            percent: 20,
            resetsAtMs: 1_791_000_000_000,
            readAtMs: 1_791_900_000_000,
            expiresAtMs: 1_793_000_000_000
        )

        #expect(try GrokBotUsageStore(directory: directory).latest(now: now) == nil)
    }

    @Test("多份缓存取最新一份，无关文件跳过")
    func newestReadingWins() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        try writeBlob(
            for: cursorSlot,
            in: directory,
            percent: 10,
            resetsAtMs: 1_793_000_000_000,
            readAtMs: 1_791_900_000_000,
            expiresAtMs: 1_793_000_000_000
        )
        try writeBlob(
            for: otherSlot,
            in: directory,
            percent: 35,
            resetsAtMs: 1_793_000_000_000,
            readAtMs: 1_792_000_000_000,
            expiresAtMs: 1_793_000_000_000
        )
        try Data("not json".utf8).write(to: directory.appendingPathComponent("other.blob"))
        try Data("{}".utf8).write(to: directory.appendingPathComponent(fileName(for: "sand.client.slice.client-meta.account-slot")))

        #expect(try GrokBotUsageStore(directory: directory).latest(now: now)?.usedPercent == 35)
    }

    @Test("排除 Cursor 登录的账号后只返回其他账号的读数")
    func excludedAccountSkipped() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        try writeBlob(
            for: cursorSlot,
            in: directory,
            percent: 10,
            resetsAtMs: 1_793_000_000_000,
            readAtMs: 1_791_900_000_000,
            expiresAtMs: 1_793_000_000_000
        )
        try writeBlob(
            for: otherSlot,
            in: directory,
            percent: 35,
            resetsAtMs: 1_793_000_000_000,
            readAtMs: 1_792_000_000_000,
            expiresAtMs: 1_793_000_000_000
        )

        let usage = try GrokBotUsageStore(directory: directory).latest(excluding: [cursorSlot], now: now)
        #expect(usage?.accountSlot == otherSlot)
        #expect(usage?.usedPercent == 35)
    }

    @Test("缓存里只有 Cursor 账号的读数时返回空")
    func excludedAccountOnly() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        try writeBlob(
            for: cursorSlot,
            in: directory,
            percent: 10,
            resetsAtMs: 1_793_000_000_000,
            readAtMs: 1_792_000_000_000,
            expiresAtMs: 1_793_000_000_000
        )

        #expect(try GrokBotUsageStore(directory: directory).latest(excluding: [cursorSlot], now: now) == nil)
    }
}
