import SwiftUI
import AiLimitsCore
import AiLimitsUI

@main
enum AiLimitsMain {
    static func main() {
        if CommandLine.arguments.contains("--dump") {
            DumpCommand.run()
        }
        AnimalFont.register()
        AiLimitsApp.main()
    }
}

struct AiLimitsApp: App {
    @StateObject private var model = LimitsViewModel()

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                Text(model.menuBarText)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
