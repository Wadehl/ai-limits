import Foundation
import Testing
@testable import AiLimitsCore

@Suite("GrokBot 用量")
struct GrokBotUsageTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbot-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeBlob(
        named name: String,
        in directory: URL,
        percent: Double,
        resetsAtMs: Double,
        readAtMs: Double,
        expiresAtMs: Double
    ) throws {
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
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: directory.appendingPathComponent(name))
    }

    @Test("读取缓存里的用量与重置时间")
    func freshReading() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        try writeBlob(
            named: "usage.blob",
            in: directory,
            percent: 64.186881,
            resetsAtMs: 1_793_000_000_000,
            readAtMs: 1_792_000_000_000,
            expiresAtMs: 1_792_086_400_000
        )

        let usage = try GrokBotUsageStore(directory: directory).read(now: now)
        #expect(usage?.usedPercent == 64.186881)
        #expect(usage?.resetsAt?.timeIntervalSince1970 == 1_793_000_000)
    }

    @Test("缓存过期后不再返回读数")
    func expiredReadingSkipped() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        try writeBlob(
            named: "usage.blob",
            in: directory,
            percent: 20,
            resetsAtMs: 1_793_000_000_000,
            readAtMs: 1_791_900_000_000,
            expiresAtMs: 1_791_986_400_000
        )

        #expect(try GrokBotUsageStore(directory: directory).read(now: now) == nil)
    }

    @Test("周期已经结束的读数不再返回")
    func passedResetSkipped() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        try writeBlob(
            named: "usage.blob",
            in: directory,
            percent: 20,
            resetsAtMs: 1_791_000_000_000,
            readAtMs: 1_791_900_000_000,
            expiresAtMs: 1_793_000_000_000
        )

        #expect(try GrokBotUsageStore(directory: directory).read(now: now) == nil)
    }

    @Test("多份缓存取最新一份，无关文件跳过")
    func newestReadingWins() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        try writeBlob(
            named: "old.blob",
            in: directory,
            percent: 10,
            resetsAtMs: 1_793_000_000_000,
            readAtMs: 1_791_900_000_000,
            expiresAtMs: 1_793_000_000_000
        )
        try writeBlob(
            named: "new.blob",
            in: directory,
            percent: 35,
            resetsAtMs: 1_793_000_000_000,
            readAtMs: 1_792_000_000_000,
            expiresAtMs: 1_793_000_000_000
        )
        try Data("not json".utf8).write(to: directory.appendingPathComponent("other.blob"))

        #expect(try GrokBotUsageStore(directory: directory).read(now: now)?.usedPercent == 35)
    }
}
