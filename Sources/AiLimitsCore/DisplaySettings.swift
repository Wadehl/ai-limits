import Foundation

/// 面板、菜单栏与桌面小组件共用的显示设置，和应用组里的额度快照放在同一个目录
public struct DisplaySettings: Codable, Sendable, Equatable {
    /// 整个账号都不展示
    public private(set) var hiddenProviders: Set<ProviderIdentifier>
    /// 被关掉的额度窗口，键是账号的标识，值是窗口标识
    private var hiddenWindows: [String: Set<String>]

    public init(
        hiddenProviders: Set<ProviderIdentifier> = [],
        hiddenWindows: [String: Set<String>] = [:]
    ) {
        self.hiddenProviders = hiddenProviders
        self.hiddenWindows = hiddenWindows
    }

    /// 旧版本的设置文件没有这一项，缺省按全部展示处理
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hiddenProviders = try container.decodeIfPresent(Set<ProviderIdentifier>.self, forKey: .hiddenProviders) ?? []
        hiddenWindows = try container.decodeIfPresent([String: Set<String>].self, forKey: .hiddenWindows) ?? [:]
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

    public func isVisible(_ provider: ProviderIdentifier) -> Bool {
        !hiddenProviders.contains(provider)
    }

    public mutating func setVisible(_ visible: Bool, for provider: ProviderIdentifier) {
        if visible {
            hiddenProviders.remove(provider)
        } else {
            hiddenProviders.insert(provider)
        }
    }

    public func isWindowVisible(_ key: String, for provider: ProviderIdentifier) -> Bool {
        hiddenWindows[provider.rawValue]?.contains(key) != true
    }

    public mutating func setWindowVisible(_ visible: Bool, key: String, for provider: ProviderIdentifier) {
        var keys = hiddenWindows[provider.rawValue] ?? []
        if visible {
            keys.remove(key)
        } else {
            keys.insert(key)
        }
        if keys.isEmpty {
            hiddenWindows.removeValue(forKey: provider.rawValue)
        } else {
            hiddenWindows[provider.rawValue] = keys
        }
    }

    /// 该账号要展示的额度窗口，整个账号被关掉时返回空
    public func visibleWindows(of limits: ProviderLimits) -> [LimitWindowEntry] {
        guard isVisible(limits.provider) else { return [] }
        return limits.orderedWindows.filter { isWindowVisible($0.key, for: limits.provider) }
    }

    /// 去掉隐藏的账号与被关掉的额度窗口；读取成功的账号一份额度都不剩时整张卡片也不再出现，
    /// 读取失败的账号仍然保留，用来显示错误
    public func applying(to providers: [ProviderLimits]) -> [ProviderLimits] {
        providers.compactMap { limits in
            guard isVisible(limits.provider) else { return nil }
            guard limits.status == .ok else { return limits }
            let windows = visibleWindows(of: limits)
            guard !windows.isEmpty else { return nil }
            return limits.keepingWindows(Set(windows.map(\.key)))
        }
    }
}
