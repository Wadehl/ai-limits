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
    /// 菜单栏当前展示第几个账号，每 6 秒往后走一个
    @Published private(set) var menuBarIndex = 0

    private let service = LimitsService()
    private let refreshInterval = Duration.seconds(300)
    private let menuBarInterval = Duration.seconds(6)
    private var loop: Task<Void, Never>?
    private var rotation: Task<Void, Never>?
    private let isSample: Bool

    init() {
        isSample = false
        // Show the last successful readings while the first network request runs.
        if let cached = try? SnapshotStore.read() {
            providers = cached.providers.filter { $0.status == .ok }
            if !providers.isEmpty { fetchedAt = cached.fetchedAt }
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                // A startup/wake failure should not linger for five minutes.
                let delay: Duration = self?.providers.contains(where: { $0.status == .error }) == true
                    ? .seconds(30) : (self?.refreshInterval ?? .seconds(300))
                do { try await Task.sleep(for: delay) } catch { break }
            }
        }
        rotation = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: self?.menuBarInterval ?? .seconds(6)) } catch { break }
                self?.advanceMenuBar()
            }
        }
    }

    /// 渲染 README 图片时使用，不读取本机数据，也不启动刷新
    init(sample: RateLimitSnapshot) {
        isSample = true
        providers = sample.providers
        fetchedAt = sample.fetchedAt
    }

    deinit {
        loop?.cancel()
        rotation?.cancel()
    }

    /// 本机没有登录凭据的 Agent 不进入列表
    var visibleProviders: [ProviderLimits] {
        providers.filter { $0.status != .unavailable }
    }

    /// 菜单栏轮流展示每个账号里剩余最多的那份额度，图标与数字来自同一个账号
    var menuBarSummary: MenuBarSummary? {
        let summaries = providers.menuBarSummaries()
        guard !summaries.isEmpty else { return nil }
        return summaries[menuBarIndex % summaries.count]
    }

    private func advanceMenuBar() {
        guard providers.menuBarSummaries().count > 1 else { return }
        menuBarIndex += 1
    }

    var menuBarText: String {
        guard let summary = menuBarSummary else { return "额度" }
        return "剩余 \(Int(summary.remainingPercent.rounded()))%"
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
        defer { isRefreshing = false }
        let snapshot = await service.fetchAll()
        guard !Task.isCancelled else { return }
        providers = snapshot.providers
        fetchedAt = snapshot.fetchedAt
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
        guard !isSample else { return }
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < 30 {
            return
        }
        await refresh()
    }
}
