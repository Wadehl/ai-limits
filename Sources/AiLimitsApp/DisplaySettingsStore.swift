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

    func isVisible(_ provider: ProviderIdentifier) -> Bool {
        settings.isVisible(provider)
    }

    func setVisible(_ visible: Bool, for provider: ProviderIdentifier) {
        guard settings.isVisible(provider) != visible else { return }
        settings.setVisible(visible, for: provider)
        save()
    }

    func isWindowVisible(_ key: String, for provider: ProviderIdentifier) -> Bool {
        settings.isWindowVisible(key, for: provider)
    }

    func setWindowVisible(_ visible: Bool, key: String, for provider: ProviderIdentifier) {
        guard settings.isWindowVisible(key, for: provider) != visible else { return }
        settings.setWindowVisible(visible, key: key, for: provider)
        save()
    }

    private func save() {
        do {
            try settings.save()
        } catch {
            fatalError("显示设置写入失败：\(error)")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
