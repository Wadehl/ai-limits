import Foundation
import AiLimitsCore

/// 无界面地读取一次额度并打印 JSON，用于本机验证取数逻辑
enum DumpCommand {
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var value: RateLimitSnapshot?

        func store(_ snapshot: RateLimitSnapshot) {
            lock.lock()
            value = snapshot
            lock.unlock()
        }

        func load() -> RateLimitSnapshot? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    static func run() -> Never {
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            box.store(await LimitsService().fetchAll())
            semaphore.signal()
        }
        semaphore.wait()

        guard let snapshot = box.load() else {
            FileHandle.standardError.write(Data("读取额度失败\n".utf8))
            exit(1)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else {
            FileHandle.standardError.write(Data("结果无法编码为 JSON\n".utf8))
            exit(1)
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(0)
    }
}
