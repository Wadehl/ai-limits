import SwiftUI
import AppKit
import AiLimitsCore
import AiLimitsUI

/// 把菜单栏面板用样例数据离屏渲染成 PNG，供 README 使用
@MainActor
enum PanelPreviewRenderer {
    static func run() {
        AnimalFont.register()
        NSApplication.shared.setActivationPolicy(.prohibited)

        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--render-panel"), arguments.count > flag + 1 else {
            fatalError("--render-panel 需要一个输出路径")
        }
        let output = URL(fileURLWithPath: arguments[flag + 1])

        let model = LimitsViewModel(sample: .sample)
        let content = PanelView(model: model, isPreview: true)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            fatalError("面板渲染失败")
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("面板 PNG 编码失败")
        }
        let colors = distinctColors(bitmap)
        guard colors >= 8 else {
            fatalError("面板图片只有 \(colors) 种颜色，版面没有画出来")
        }
        let covered = coveredRatio(bitmap)
        guard covered >= 0.05 else {
            fatalError("面板图片只有 \(Int(covered * 100))% 的像素和底色不同，内容被吞掉了")
        }
        do {
            try png.write(to: output)
        } catch {
            fatalError("面板写入 \(output.path) 失败：\(error)")
        }
        print("\(bitmap.pixelsWide)x\(bitmap.pixelsHigh) 颜色数 \(colors) 内容占比 \(Int(covered * 100))% \(output.path)")
    }

    private static func distinctColors(_ bitmap: NSBitmapImageRep) -> Int {
        var seen = Set<UInt32>()
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 8) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 8) {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                let red = UInt32(color.redComponent * 255) << 16
                let green = UInt32(color.greenComponent * 255) << 8
                let blue = UInt32(color.blueComponent * 255)
                seen.insert(red | green | blue)
            }
        }
        return seen.count
    }

    private static func coveredRatio(_ bitmap: NSBitmapImageRep) -> Double {
        guard let corner = bitmap.colorAt(x: 1, y: 1) else {
            fatalError("位图左上角取不到颜色")
        }
        var covered = 0
        var total = 0
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                total += 1
                let tolerance = 6.0 / 255
                let same = abs(color.redComponent - corner.redComponent) < tolerance
                    && abs(color.greenComponent - corner.greenComponent) < tolerance
                    && abs(color.blueComponent - corner.blueComponent) < tolerance
                if !same { covered += 1 }
            }
        }
        return total == 0 ? 0 : Double(covered) / Double(total)
    }
}
