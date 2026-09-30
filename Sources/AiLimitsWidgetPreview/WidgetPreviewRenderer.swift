import SwiftUI
import AppKit
import WidgetKit
import AiLimitsCore
import AiLimitsUI

/// 小组件无法在开发机上直接预览，这里把三种尺寸在三种绘制方式下离屏渲染成 PNG，用来检查版面
@main
enum WidgetPreviewRenderer {
    private struct Layout {
        let family: WidgetFamily
        let size: CGSize
        let name: String
    }

    /// 系统调暗小组件之后由系统提供底色，离屏渲染只能用一个中间色调的底来近似
    private struct Appearance {
        let mode: WidgetRenderingMode
        let backdrop: Color
        let name: String
    }

    @MainActor
    private static let layouts = [
        Layout(family: .systemSmall, size: CGSize(width: 170, height: 170), name: "systemSmall"),
        Layout(family: .systemMedium, size: CGSize(width: 364, height: 170), name: "systemMedium"),
        Layout(family: .systemLarge, size: CGSize(width: 364, height: 382), name: "systemLarge")
    ]

    @MainActor
    private static let appearances = [
        Appearance(mode: .fullColor, backdrop: AnimalPalette.background, name: "fullColor"),
        Appearance(mode: .accented, backdrop: Color(white: 0.18), name: "accented-dark"),
        Appearance(mode: .accented, backdrop: Color(white: 0.5), name: "accented-mid"),
        Appearance(mode: .accented, backdrop: Color(white: 0.82), name: "accented-light"),
        Appearance(mode: .vibrant, backdrop: Color(white: 0.18), name: "vibrant-dark"),
        Appearance(mode: .vibrant, backdrop: Color(white: 0.5), name: "vibrant-mid"),
        Appearance(mode: .vibrant, backdrop: Color(white: 0.82), name: "vibrant-light")
    ]

    @MainActor
    static func main() {
        AnimalFont.register()
        NSApplication.shared.setActivationPolicy(.prohibited)

        let directory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "widget-preview")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            fatalError("输出目录 \(directory.path) 创建失败：\(error)")
        }

        for layout in layouts {
            for appearance in appearances {
                let name = "\(layout.name)-\(appearance.name)"
                render(layout, appearance, to: directory.appendingPathComponent("\(name).png"), name: name)
            }
        }
    }

    @MainActor
    private static func render(_ layout: Layout, _ appearance: Appearance, to url: URL, name: String) {
        let entry = LimitsEntry(date: Date(), data: .ready(.sample))
        let content = ZStack {
            appearance.backdrop
            WidgetLayoutView(entry: entry, family: layout.family)
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .environment(\.widgetRenderingMode, appearance.mode)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage else {
            fatalError("\(name) 渲染失败")
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
            fatalError("\(name) 位图转换失败")
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("\(name) PNG 编码失败")
        }
        do {
            try png.write(to: url)
        } catch {
            fatalError("\(name) 写入 \(url.path) 失败：\(error)")
        }

        let colors = distinctColors(bitmap)
        guard colors > 4 else {
            fatalError("\(name) 只有 \(colors) 种颜色，版面没有画出来")
        }
        let margin = contentMargin(bitmap)
        guard margin >= 2 else {
            fatalError("\(name) 内容离边缘只有 \(margin) 像素，版面被挤满或者裁切")
        }
        let covered = coveredRatio(bitmap)
        guard covered >= 0.08 else {
            fatalError("\(name) 只有 \(Int(covered * 100))% 的像素和底色不同，内容被底色吞掉了")
        }
        let span = luminanceSpan(bitmap)
        guard span >= 0.1 else {
            fatalError("\(name) 明暗差别只有 \(span)，内容被压成一片了")
        }
        print("\(name) \(bitmap.pixelsWide)x\(bitmap.pixelsHigh) 颜色数 \(colors) 边缘留白 \(margin) 像素 内容占比 \(Int(covered * 100))% 明暗差别 \(String(format: "%.2f", span)) \(url.path)")
    }

    private static func distinctColors(_ bitmap: NSBitmapImageRep) -> Int {
        var seen = Set<UInt32>()
        let step = 8
        for x in stride(from: 0, to: bitmap.pixelsWide, by: step) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: step) {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                let red = UInt32(color.redComponent * 255) << 16
                let green = UInt32(color.greenComponent * 255) << 8
                let blue = UInt32(color.blueComponent * 255)
                seen.insert(red | green | blue)
            }
        }
        return seen.count
    }

    /// 离边缘最近的、和四角底色不同的像素的距离，用来发现版面被挤满或者裁掉
    private static func contentMargin(_ bitmap: NSBitmapImageRep) -> Int {
        guard let corner = bitmap.colorAt(x: 1, y: 1) else {
            fatalError("位图左上角取不到颜色")
        }
        var minMargin = Int.max
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                if isSame(color, corner) { continue }
                minMargin = min(minMargin, x, y, bitmap.pixelsWide - 1 - x, bitmap.pixelsHigh - 1 - y)
            }
        }
        return minMargin == Int.max ? 0 : minMargin
    }

    /// 和底色不同的像素占的比例，含量为零说明内容被底色吞掉了
    private static func coveredRatio(_ bitmap: NSBitmapImageRep) -> Double {
        guard let corner = bitmap.colorAt(x: 1, y: 1) else {
            fatalError("位图左上角取不到颜色")
        }
        var covered = 0
        var total = 0
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                total += 1
                if !isSame(color, corner) { covered += 1 }
            }
        }
        return total == 0 ? 0 : Double(covered) / Double(total)
    }

    /// 画面里最亮和最暗的像素差多少，用来发现内容被压成一个颜色
    private static func luminanceSpan(_ bitmap: NSBitmapImageRep) -> Double {
        var low = 1.0
        var high = 0.0
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
                low = min(low, luminance)
                high = max(high, luminance)
            }
        }
        return high - low
    }

    private static func isSame(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        let tolerance = 6.0 / 255
        return abs(lhs.redComponent - rhs.redComponent) < tolerance
            && abs(lhs.greenComponent - rhs.greenComponent) < tolerance
            && abs(lhs.blueComponent - rhs.blueComponent) < tolerance
    }
}
