import SwiftUI
import CoreText
import AppKit

/// animal-island-ui 的配色，取自设计系统的 CSS 变量
public enum AnimalPalette {
    public static let primary = Color(hex: 0x19C8B9)
    public static let primaryActive = Color(hex: 0x11A89B)
    public static let primaryBackground = Color(hex: 0xE6F9F6)

    public static let textTitle = Color(hex: 0x794F27)
    public static let textBody = Color(hex: 0x725D42)
    public static let textMuted = Color(hex: 0x8A7B66)
    public static let textDisabled = Color(hex: 0xC4B89E)

    public static let background = Color(hex: 0xF8F8F0)
    public static let backgroundContent = Color(red: 247 / 255, green: 243 / 255, blue: 223 / 255)

    public static let border = Color(hex: 0xC4B89E)
    public static let borderSoft = Color(hex: 0xDCD8D1)
    public static let dot = Color(hex: 0xC4B89E)

    public static let success = Color(hex: 0x6FBA2C)
    public static let warning = Color(hex: 0xF5C31C)
    public static let error = Color(hex: 0xE05A5A)
    public static let focusYellow = Color(hex: 0xFFCC00)

    public static let shadowSoft = Color(hex: 0x3D3428).opacity(0.06)
    public static let shadowSoftHover = Color(hex: 0x3D3428).opacity(0.1)
    public static let trackShadow = Color(red: 114 / 255, green: 93 / 255, blue: 66 / 255)

    /// 消耗到达这两个百分比后改用状态色
    public static func usageColor(usedPercent: Double) -> Color {
        switch usedPercent {
        case 90...: error
        case 70..<90: warning
        default: primary
        }
    }
}

public enum AnimalRadius {
    public static let small: CGFloat = 12
    public static let card: CGFloat = 20
}

public extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// 设计规范要求的 Nunito 字体，随应用一起打包，字重通过可变字体的 wght 轴设置
public enum AnimalFont {
    private static let postScriptName = "Nunito-ExtraLight"
    private static let weightAxis = 0x77676874 // 'wght'
    private static let fileName = "Nunito"
    private static let fileExtension = "ttf"

    public static func register() {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension) else {
            fatalError("应用包里缺少字体文件 \(fileName).\(fileExtension)")
        }
        var error: Unmanaged<CFError>?
        guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else {
            fatalError("字体 \(fileName) 注册失败：\(String(describing: error?.takeRetainedValue()))")
        }
    }

    public static func font(size: CGFloat, weight: CGFloat) -> Font {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .name: postScriptName,
            .variation: [NSNumber(value: weightAxis): weight]
        ])
        guard let font = NSFont(descriptor: descriptor, size: size) else {
            fatalError("Nunito 字重 \(weight) 无法创建")
        }
        return Font(font)
    }

    public static func body(_ size: CGFloat = 13) -> Font { font(size: size, weight: 500) }
    public static func emphasis(_ size: CGFloat = 13) -> Font { font(size: size, weight: 700) }
    public static func heading(_ size: CGFloat = 15) -> Font { font(size: size, weight: 800) }
    public static func ribbon(_ size: CGFloat = 15) -> Font { font(size: size, weight: 900) }
}

public enum AnimalMotion {
    public static let ease = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.25)
    public static let fill = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.6)
}
