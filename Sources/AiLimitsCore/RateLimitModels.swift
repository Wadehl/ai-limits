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

/// 固定窗口在显示设置里使用的标识，界面上的名称改了也不影响已经保存的选择
public enum LimitWindowKey {
    public static let session = "session"
    public static let weekly = "weekly"
    public static let monthly = "monthly"
}

/// 某个账号的一份额度窗口，附带标识与展示名称
public struct LimitWindowEntry: Sendable, Equatable {
    public let key: String
    public let name: String
    public let window: RateLimitWindow

    public init(key: String, name: String, window: RateLimitWindow) {
        self.key = key
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

    /// 该账号已取到的全部额度窗口，附带标识与展示名称
    public var orderedWindows: [LimitWindowEntry] {
        var items: [LimitWindowEntry] = []
        if let session {
            items.append(LimitWindowEntry(key: LimitWindowKey.session, name: "5 小时", window: session))
        }
        if let weekly {
            items.append(LimitWindowEntry(key: LimitWindowKey.weekly, name: "7 天", window: weekly))
        }
        if let monthly {
            items.append(LimitWindowEntry(key: LimitWindowKey.monthly, name: "月度", window: monthly))
        }
        for bucket in buckets {
            items.append(LimitWindowEntry(key: bucket.name, name: bucket.name, window: bucket.window))
        }
        return items
    }

    /// 只留下给定标识的额度窗口，其余字段原样保留
    public func keepingWindows(_ keys: Set<String>) -> ProviderLimits {
        ProviderLimits(
            provider: provider,
            session: keys.contains(LimitWindowKey.session) ? session : nil,
            weekly: keys.contains(LimitWindowKey.weekly) ? weekly : nil,
            monthly: keys.contains(LimitWindowKey.monthly) ? monthly : nil,
            buckets: buckets.filter { keys.contains($0.name) },
            planType: planType,
            accountLabel: accountLabel,
            status: status,
            error: error,
            updatedAt: updatedAt
        )
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
