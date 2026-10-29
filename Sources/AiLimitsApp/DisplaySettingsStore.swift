import SwiftUI
import WidgetKit
import AiLimitsCore

@MainActor
final class DisplaySettingsStore: ObservableObject {
    @Published private(set) var settings: DisplaySettings

    init(settings: DisplaySettings? = nil) {
        if let settings {
            self.settings = settings
            return
        }
        do {
            self.settings = try DisplaySettings.load()
        } catch {
            fatalError("显示设置读取失败：\(error)")
        }
    }

    func showsProgressBar(for provider: ProviderIdentifier) -> Bool {
        settings.showsProgressBar(for: provider)
    }

    func setShowsProgressBar(_ shows: Bool, for provider: ProviderIdentifier) {
        guard settings.showsProgressBar(for: provider) != shows else { return }
        settings.setShowsProgressBar(shows, for: provider)
        do {
            try settings.save()
        } catch {
            fatalError("显示设置写入失败：\(error)")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
