import SwiftUI
import AiLimitsCore
import AiLimitsUI

@main
enum AiLimitsMain {
    static func main() {
        if CommandLine.arguments.contains("--dump") {
            DumpCommand.run()
        }
        if CommandLine.arguments.contains("--render-panel") {
            MainActor.assumeIsolated { PanelPreviewRenderer.run() }
            exit(0)
        }
        if CommandLine.arguments.contains("--render-settings") {
            MainActor.assumeIsolated { SettingsPreviewRenderer.run() }
            exit(0)
        }
        AnimalFont.register()
        AiLimitsApp.main()
    }
}

struct AiLimitsApp: App {
    @StateObject private var model = LimitsViewModel()
    @StateObject private var display = DisplaySettingsStore()

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model, display: display)
        } label: {
            MenuBarLabel(model: model, display: display)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(display: display, model: model)
        }
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var model: LimitsViewModel
    @ObservedObject var display: DisplaySettingsStore

    var body: some View {
        HStack(spacing: 4) {
            if let summary = model.menuBarSummary(using: display.settings) {
                Image(nsImage: ProviderIconAssets.menuBarImage(for: summary.provider, pointSize: 14))
                    .renderingMode(.template)
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
            }
            Text(model.menuBarText(using: display.settings))
        }
        .accessibilityLabel(model.menuBarText(using: display.settings))
    }
}
