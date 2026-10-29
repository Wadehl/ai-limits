import Foundation

/// 面板与桌面小组件共用的显示设置，和应用组里的额度快照放在同一个目录
public struct DisplaySettings: Codable, Sendable, Equatable {
    /// 关掉进度条的账号，百分比照常展示
    public var hiddenProgressBarProviders: Set<ProviderIdentifier>

    public init(hiddenProgressBarProviders: Set<ProviderIdentifier> = []) {
        self.hiddenProgressBarProviders = hiddenProgressBarProviders
    }

    public static var fileURL: URL {
        get throws { try SnapshotStore.directoryURL.appendingPathComponent("display-settings.json") }
    }

    /// 文件尚未生成时返回默认设置
    public static func load() throws -> DisplaySettings {
        let url = try fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return DisplaySettings()
        }
        return try JSONDecoder().decode(DisplaySettings.self, from: Data(contentsOf: url))
    }

    public func save() throws {
        let url = try Self.fileURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    public func showsProgressBar(for provider: ProviderIdentifier) -> Bool {
        !hiddenProgressBarProviders.contains(provider)
    }

    public mutating func setShowsProgressBar(_ shows: Bool, for provider: ProviderIdentifier) {
        if shows {
            hiddenProgressBarProviders.remove(provider)
        } else {
            hiddenProgressBarProviders.insert(provider)
        }
    }
}
