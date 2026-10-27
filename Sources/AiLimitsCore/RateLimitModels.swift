import Foundation

public struct RateLimitWindow: Sendable, Codable, Equatable {
    public let usedPercent: Double
    public let windowMinutes: Int
    public let resetsAt: Date?
    public let resetDescription: String?

    public init(usedPercent: Double, windowMinutes: Int, resetsAt: Date?, resetDescription: String?) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
    }

    /// 还剩多少可用，界面上的进度条与百分比都按它展示
    public var remainingPercent: Double {
        max(0, 100 - usedPercent)
    }
}

public struct RateLimitBucket: Sendable, Codable, Equatable {
    public let name: String
    public let window: RateLimitWindow

    public init(name: String, window: RateLimitWindow) {
        self.name = name
        self.window = window
    }
}

public enum ProviderIdentifier: String, Sendable, Codable, CaseIterable {
    case claude
    case codex
    case cursor
    case grok

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .grok: "Grok"
        }
    }
}

public enum ProviderStatus: String, Sendable, Codable {
    /// 已取到额度数据
    case ok
    /// 本机没有该工具的登录凭据，或者该账号没有可展示的额度
    case unavailable
    /// 请求或者解析失败
    case error
}

public struct ProviderLimits: Sendable, Codable, Equatable {
    public let provider: ProviderIdentifier
    public let session: RateLimitWindow?
    public let weekly: RateLimitWindow?
    public let monthly: RateLimitWindow?
    public let buckets: [RateLimitBucket]
    public let planType: String?
    public let accountLabel: String?
    public let status: ProviderStatus
    public let error: String?
    public let updatedAt: Date

    public init(
        provider: ProviderIdentifier,
        session: RateLimitWindow? = nil,
        weekly: RateLimitWindow? = nil,
        monthly: RateLimitWindow? = nil,
        buckets: [RateLimitBucket] = [],
        planType: String? = nil,
        accountLabel: String? = nil,
        status: ProviderStatus,
        error: String? = nil,
        updatedAt: Date
    ) {
        self.provider = provider
        self.session = session
        self.weekly = weekly
        self.monthly = monthly
        self.buckets = buckets
        self.planType = planType
        self.accountLabel = accountLabel
        self.status = status
        self.error = error
        self.updatedAt = updatedAt
    }

    /// 该账号已取到的全部额度窗口，附带展示名称
    public var orderedWindows: [(name: String, window: RateLimitWindow)] {
        var items: [(name: String, window: RateLimitWindow)] = []
        if let session { items.append(("5 小时", session)) }
        if let weekly { items.append(("7 天", weekly)) }
        if let monthly { items.append(("月度", monthly)) }
        for bucket in buckets { items.append((bucket.name, bucket.window)) }
        return items
    }
}

public struct RateLimitSnapshot: Sendable, Codable, Equatable {
    public let providers: [ProviderLimits]
    public let fetchedAt: Date

    public init(providers: [ProviderLimits], fetchedAt: Date) {
        self.providers = providers
        self.fetchedAt = fetchedAt
    }
}
