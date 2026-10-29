import SwiftUI
import AiLimitsCore
import AiLimitsUI

struct PanelView: View {
    @ObservedObject var model: LimitsViewModel
    @ObservedObject var display: DisplaySettingsStore

    /// README 图片离屏渲染时去掉滚动区域，让面板按内容自然展开
    var isPreview = false

    @Environment(\.openSettings) private var openSettings

    /// 列表最高高度，超出后由 ScrollView 滚动
    private let maxListHeight: CGFloat = 430

    @State private var listHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                RibbonTitle(text: "Agent 额度")
                Spacer(minLength: 0)
                Text(model.updatedText)
                    .font(AnimalFont.body(11))
                    .foregroundStyle(AnimalPalette.textMuted)
            }
            .padding(.leading, 8)

            if let cacheError = model.cacheError {
                Text(cacheError)
                    .font(AnimalFont.body(11))
                    .foregroundStyle(AnimalPalette.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isPreview {
                cardList
            } else {
                ScrollView {
                    cardList
                }
                .frame(height: min(max(listHeight, 1), maxListHeight))
                .scrollIndicators(.never)
                .onPreferenceChange(PanelListHeightKey.self) { height in
                    listHeight = height
                }
            }

            HStack(spacing: 10) {
                AnimalButton(title: model.isRefreshing ? "刷新中…" : "刷新", kind: .primary) {
                    Task { await model.refresh() }
                }
                .disabled(model.isRefreshing)

                AnimalButton(title: "设置", kind: .plain) {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openSettings()
                }

                AnimalButton(title: "退出", kind: .plain) {
                    NSApplication.shared.terminate(nil)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(width: 380)
        .background(AnimalPalette.background)
        .task { await model.refreshIfStale() }
    }

    private var cardList: some View {
        VStack(spacing: 12) {
            ForEach(model.visibleProviders, id: \.provider) { limits in
                ProviderCard(
                    limits: limits,
                    showsProgressBar: display.showsProgressBar(for: limits.provider)
                )
            }
            if model.visibleProviders.isEmpty {
                Text(model.fetchedAt == nil ? "正在读取本机额度…" : "本机没有检测到已登录的 Agent")
                    .font(AnimalFont.body(13))
                    .foregroundStyle(AnimalPalette.textMuted)
                    .padding(.vertical, 24)
            }
        }
        .padding(.vertical, 4)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PanelListHeightKey.self, value: proxy.size.height)
            }
        )
    }
}

/// 面板列表的自然高度，用来给 ScrollView 一个确定的高度
private struct PanelListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct AnimalButton: View {
    enum Kind {
        case primary
        case plain
    }

    let title: String
    let kind: Kind
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AnimalFont.font(size: 13, weight: 600))
                .foregroundStyle(foreground)
                .padding(.horizontal, 18)
                .frame(height: 34)
                .background(background)
                .overlay(Capsule().stroke(borderColor, lineWidth: 2))
                .clipShape(Capsule())
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
                .offset(y: hovered && isEnabled ? -1 : 0)
                .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .animation(AnimalMotion.ease, value: hovered)
        .onHover { hovered = $0 }
    }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .plain: hovered && isEnabled ? AnimalPalette.primary : AnimalPalette.textTitle
        }
    }

    private var background: Color {
        switch kind {
        case .primary: AnimalPalette.primary
        case .plain: AnimalPalette.background
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary: AnimalPalette.primaryActive
        case .plain: hovered && isEnabled ? AnimalPalette.primary : AnimalPalette.borderSoft
        }
    }

    /// 两种按钮共用同一套阴影与高度，主次只由配色区分
    private var shadowColor: Color {
        guard isEnabled else { return .clear }
        return hovered ? AnimalPalette.shadowSoftHover : AnimalPalette.shadowSoft
    }

    private var shadowRadius: CGFloat {
        hovered && isEnabled ? 10 : 4
    }

    private var shadowY: CGFloat {
        hovered && isEnabled ? 3 : 2
    }
}
