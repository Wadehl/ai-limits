import WidgetKit
import AiLimitsCore
import AiLimitsUI

struct LimitsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> LimitsEntry {
        LimitsEntry(date: Date(), data: .ready(.sample))
    }

    func getSnapshot(in context: Context, completion: @escaping (LimitsEntry) -> Void) {
        completion(context.isPreview ? LimitsEntry(date: Date(), data: .ready(.sample)) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LimitsEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .after(Date().addingTimeInterval(300))))
    }

    private func current() -> LimitsEntry {
        let display: DisplaySettings
        do {
            display = try DisplaySettings.load()
        } catch {
            return LimitsEntry(date: Date(), data: .failed("显示设置无法读取"), display: DisplaySettings())
        }
        do {
            guard let snapshot = try SnapshotStore.read() else {
                return LimitsEntry(date: Date(), data: .empty, display: display)
            }
            return LimitsEntry(date: Date(), data: .ready(snapshot), display: display)
        } catch {
            return LimitsEntry(date: Date(), data: .failed("额度数据无法读取"), display: display)
        }
    }
}
