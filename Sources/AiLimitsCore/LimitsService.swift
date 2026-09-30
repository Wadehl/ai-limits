import Foundation

public protocol LimitsProvider: Sendable {
    var identifier: ProviderIdentifier { get }
    func fetch() async throws -> ProviderLimits
}

extension ClaudeLimitsProvider: LimitsProvider {
    public var identifier: ProviderIdentifier { .claude }
}

extension CodexLimitsProvider: LimitsProvider {
    public var identifier: ProviderIdentifier { .codex }
}

extension CursorLimitsProvider: LimitsProvider {
    public var identifier: ProviderIdentifier { .cursor }
}

extension GrokLimitsProvider: LimitsProvider {
    public var identifier: ProviderIdentifier { .grok }
}

public struct LimitsService: Sendable {
    public init() {}

    /// 同时读取本机各个 Agent 的额度，单个工具失败只影响它自己的那一条
    public func fetchAll() async -> RateLimitSnapshot {
        async let claude = result(of: ClaudeLimitsProvider())
        async let codex = result(of: CodexLimitsProvider())
        async let cursor = result(of: CursorLimitsProvider())
        async let grok = result(of: GrokLimitsProvider())
        let providers = await [claude, codex, cursor, grok]
        return RateLimitSnapshot(providers: providers, fetchedAt: Date())
    }

    private func result(of provider: some LimitsProvider) async -> ProviderLimits {
        do {
            return try await provider.fetch()
        } catch {
            return ProviderLimits(
                provider: provider.identifier,
                status: .error,
                error: String(describing: error),
                updatedAt: Date()
            )
        }
    }
}
