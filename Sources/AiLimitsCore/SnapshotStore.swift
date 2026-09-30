import Foundation

/// 应用与桌面小组件之间共享的一份额度快照
public enum SnapshotStore {
    /// macOS 要求应用组的标识前面带上开发者团队编号，否则系统拒绝共享目录
    public static let appGroupIdentifier = "52BF5GV693.group.com.kevinkwok.ailimits"

    public static var directoryURL: URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            fatalError("应用组 \(appGroupIdentifier) 无法定位共享目录")
        }
        return url
    }

    public static var fileURL: URL {
        directoryURL.appendingPathComponent("snapshot.json")
    }

    public static func write(_ snapshot: RateLimitSnapshot) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    /// 文件尚未生成时返回 nil
    public static func read() throws -> RateLimitSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try decoder.decode(RateLimitSnapshot.self, from: Data(contentsOf: fileURL))
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
