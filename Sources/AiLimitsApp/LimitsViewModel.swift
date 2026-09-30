import Foundation
import SwiftUI
import WidgetKit
import AiLimitsCore

@MainActor
final class LimitsViewModel: ObservableObject {
    @Published private(set) var providers: [ProviderLimits] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var cacheError: String?

    private let service = LimitsService()
    private let refreshInterval = Duration.seconds(300)
    private var loop: Task<Void, Never>?

    init() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: self?.refreshInterval ?? .seconds(300))
            }
        }
    }

    deinit {
        loop?.cancel()
    }

    /// 本机没有登录凭据的 Agent 不进入列表
    var visibleProviders: [ProviderLimits] {
        providers.filter { $0.status != .unavailable }
    }

    var peakUsedPercent: Double? {
        providers
            .filter { $0.status == .ok }
            .flatMap { $0.orderedWindows.map(\.window.usedPercent) }
            .max()
    }

    var menuBarText: String {
        guard let peak = peakUsedPercent else { return "额度" }
        return "\(Int(peak.rounded()))%"
    }

    var updatedText: String {
        guard let fetchedAt else { return "尚未取到数据" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return "更新于 \(formatter.string(from: fetchedAt))"
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let snapshot = await service.fetchAll()
        providers = snapshot.providers
        fetchedAt = snapshot.fetchedAt
        isRefreshing = false
        publish(snapshot)
    }

    /// 把快照写给桌面小组件，并让它立刻重画
    private func publish(_ snapshot: RateLimitSnapshot) {
        do {
            try SnapshotStore.write(snapshot)
            cacheError = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            cacheError = "桌面小组件拿不到数据：\(error)"
        }
    }

    /// 面板每次打开时刷新，短时间内重复打开则沿用已有结果
    func refreshIfStale() async {
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < 30 {
            return
        }
        await refresh()
    }
}
