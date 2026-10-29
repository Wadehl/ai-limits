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
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(display: display)
        }
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var model: LimitsViewModel

    var body: some View {
        HStack(spacing: 5) {
            if let summary = model.menuBarSummary {
                ProviderIcon(provider: summary.provider, color: .primary)
                    .frame(width: 13, height: 13)
            }
            Text(model.menuBarText)
        }
    }
}
