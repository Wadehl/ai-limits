import Testing
import AppKit
import SwiftUI
import WidgetKit
@testable import AiLimitsUI

@Suite("小组件用色")
struct WidgetInkTests {
    @Test("系统调暗之后改用单色绘制")
    func resolveMode() {
        #expect(alpha(WidgetInk.resolve(.fullColor).cardFill) == 1)
        #expect(alpha(WidgetInk.resolve(.accented).cardFill) < 1)
        #expect(alpha(WidgetInk.resolve(.vibrant).cardFill) < 1)
    }

    /// 系统把整份内容当作模板时只看透明度，文字和格子底色的透明度相同就等于什么都没有
    @Test("单色绘制下文字和格子底色靠透明度分开")
    func monochromeTextStaysVisible() {
        let ink = WidgetInk.monochrome
        let card = alpha(ink.cardFill)
        #expect(card < 1)
        for text in [ink.title, ink.body, ink.muted, ink.disabled, ink.error] {
            #expect(alpha(text) != card)
        }
        #expect(alpha(ink.title) != alpha(ink.body))
        #expect(alpha(ink.body) != alpha(ink.muted))
        #expect(alpha(ink.muted) != alpha(ink.disabled))
        #expect(alpha(ink.tagText) != alpha(ink.tagFill))
    }

    @Test("单色绘制下进度条的轨道和填充分开")
    func monochromeBarStaysVisible() {
        let ink = WidgetInk.monochrome
        #expect(alpha(ink.barTrack) < 1)
        #expect(alpha(ink.barFill ?? .clear) == 1)
        #expect(alpha(ink.barTrack) != alpha(ink.barFill ?? .clear))
    }

    @Test("全彩绘制仍然是设计系统的奶油配色")
    func fullColorKeepsDesignPalette() {
        let ink = WidgetInk.fullColor
        #expect(ink.cardFill == AnimalPalette.backgroundContent)
        #expect(ink.title == AnimalPalette.textTitle)
        #expect(ink.body == AnimalPalette.textBody)
        #expect(ink.muted == AnimalPalette.textMuted)
        #expect(ink.disabled == AnimalPalette.textDisabled)
        #expect(ink.error == AnimalPalette.error)
        #expect(ink.barFill == nil)
        #expect(ink.texturedBar)
    }

    private func alpha(_ color: Color) -> Double {
        guard let resolved = NSColor(color).usingColorSpace(.sRGB) else {
            fatalError("颜色 \(color) 转换不到 sRGB")
        }
        return Double(resolved.alphaComponent)
    }
}
