import SwiftUI
import AppKit
import AiLimitsCore

/// 账号图标，取自 LobeHub 图标库的单色图形，渲染时按前景色着色
public struct ProviderIcon: View {
    public let provider: ProviderIdentifier
    public var color: Color

    public init(provider: ProviderIdentifier, color: Color = .primary) {
        self.provider = provider
        self.color = color
    }

    public var body: some View {
        Image(nsImage: ProviderIconAssets.image(for: provider))
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

@MainActor
public enum ProviderIconAssets {
    private static let images: [ProviderIdentifier: NSImage] = Dictionary(
        uniqueKeysWithValues: ProviderIdentifier.allCases.map { ($0, load($0)) }
    )

    public static func image(for provider: ProviderIdentifier) -> NSImage {
        guard let image = images[provider] else {
            fatalError("缺少 \(provider.rawValue) 图标")
        }
        return image
    }

    private static func load(_ provider: ProviderIdentifier) -> NSImage {
        let name = provider.rawValue
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "ProviderIcons"),
            Bundle.main.url(forResource: name, withExtension: "png")
        ]
        for url in candidates.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: url) {
                image.isTemplate = true
                return image
            }
        }
        fatalError("应用包里缺少 \(name).png 图标")
    }

    /// 菜单栏使用的图标：先按目标尺寸画进位图，再交给系统当作模板图着色，
    /// 避免系统状态栏直接缩放 256 点原图。
    public static func menuBarImage(for provider: ProviderIdentifier, pointSize: CGFloat) -> NSImage {
        let scale: CGFloat = 2
        let pixels = Int(pointSize * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            fatalError("菜单栏图标位图创建失败")
        }
        rep.size = NSSize(width: pointSize, height: pointSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image(for: provider).draw(
            in: NSRect(x: 0, y: 0, width: pointSize, height: pointSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: NSSize(width: pointSize, height: pointSize))
        result.addRepresentation(rep)
        result.isTemplate = true
        return result
    }
}
