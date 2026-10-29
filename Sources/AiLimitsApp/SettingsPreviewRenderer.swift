import SwiftUI
import AppKit
import AiLimitsCore
import AiLimitsUI

/// 把设置页面用样例数据离屏渲染成 PNG，用来检查版面
@MainActor
enum SettingsPreviewRenderer {
    static func run() {
        AnimalFont.register()
        NSApplication.shared.setActivationPolicy(.prohibited)

        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--render-settings"), arguments.count > flag + 1 else {
            fatalError("--render-settings 需要一个输出路径")
        }
        let output = URL(fileURLWithPath: arguments[flag + 1])

        let display = DisplaySettingsStore(settings: DisplaySettings())
        let content = SettingsView(display: display)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            fatalError("设置页面渲染失败")
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("设置页面 PNG 编码失败")
        }
        do {
            try png.write(to: output)
        } catch {
            fatalError("设置页面写入 \(output.path) 失败：\(error)")
        }
        print("\(bitmap.pixelsWide)x\(bitmap.pixelsHigh) \(output.path)")
    }
}
