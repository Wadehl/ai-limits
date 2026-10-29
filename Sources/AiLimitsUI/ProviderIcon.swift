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
                return image
            }
        }
        fatalError("应用包里缺少 \(name).png 图标")
    }
}
