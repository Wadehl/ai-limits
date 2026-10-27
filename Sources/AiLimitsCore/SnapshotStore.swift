import Foundation

/// 应用与桌面小组件之间共享的一份额度快照
///
/// 共享位置有两种，构建时通过 Info.plist 的 `AiLimitsSharedStorage` 选定，应用与小组件扩展必须一致：
/// - `appGroup`：应用组共享目录。需要真实的开发者团队编号签名，macOS 15 起系统按团队编号校验应用组，
///   临时签名（ad-hoc）的小组件扩展会被直接拒绝访问。
/// - `local`：`~/Library/Application Support/AiLimits/`。给没有付费开发者账号的临时签名构建使用，
///   小组件扩展通过沙盒的只读临时例外读取这个目录，不依赖团队编号。
public enum SnapshotStore {
    public enum Storage: String, Sendable {
        case appGroup
        case local
    }

    /// Info.plist 里没有 `AiLimitsAppGroup` 时使用的应用组标识
    /// macOS 要求应用组的标识前面带上开发者团队编号，否则系统拒绝共享目录
    public static let defaultAppGroupIdentifier = "52BF5GV693.group.com.kevinkwok.ailimits"

    /// 小组件扩展的沙盒例外按这个相对主目录的路径授权，与 project.yml 保持一致
    public static let localRelativePath = "Library/Application Support/AiLimits"

    public static var appGroupIdentifier: String {
        infoValue("AiLimitsAppGroup") ?? defaultAppGroupIdentifier
    }

    public static var storage: Storage {
        infoValue("AiLimitsSharedStorage").flatMap(Storage.init(rawValue:)) ?? .appGroup
    }

    public static var directoryURL: URL {
        get throws {
            switch storage {
            case .appGroup:
                guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
                    throw LimitsError.requestFailed("应用组共享目录暂时不可用")
                }
                return url
            case .local:
                return realHomeDirectory.appending(path: localRelativePath, directoryHint: .isDirectory)
            }
        }
    }

    public static var fileURL: URL {
        get throws { try directoryURL.appendingPathComponent("snapshot.json") }
    }

    public static func write(_ snapshot: RateLimitSnapshot) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    /// 文件尚未生成时返回 nil
    public static func read() throws -> RateLimitSnapshot? {
        guard try FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try decoder.decode(RateLimitSnapshot.self, from: Data(contentsOf: fileURL))
    }

    /// 沙盒里的 `homeDirectoryForCurrentUser` 指向扩展自己的容器，沙盒例外却按真实主目录授权，所以从账户信息里取
    static var realHomeDirectory: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
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
