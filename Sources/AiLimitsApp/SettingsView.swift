import SwiftUI
import AiLimitsCore
import AiLimitsUI

struct SettingsView: View {
    @ObservedObject var display: DisplaySettingsStore
    @ObservedObject var model: LimitsViewModel
    @StateObject private var launch = LaunchAtLogin()

    /// README 图片离屏渲染时按内容自然展开，不受滚动区域限制
    var isPreview = false

    /// 账号与额度都列出来之后可能比屏幕还高，超出后滚动
    private let maxHeight: CGFloat = 620

    var body: some View {
        if isPreview {
            content
        } else {
            ScrollView {
                content
            }
            .frame(width: 380, height: maxHeight)
            .scrollIndicators(.never)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            RibbonTitle(text: "设置")
                .padding(.leading, 8)

            startupCard
            visibilityCard

            Text("这里的开关同时作用于菜单栏面板、桌面小组件与菜单栏上轮换的额度。")
                .font(AnimalFont.body(11))
                .foregroundStyle(AnimalPalette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 380, alignment: .leading)
        .background(AnimalPalette.background)
        .onAppear { launch.refresh() }
    }

    private var startupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("启动")
                .font(AnimalFont.heading(14))
                .foregroundStyle(AnimalPalette.textTitle)

            Toggle(isOn: Binding(
                get: { launch.isEnabled },
                set: { launch.setEnabled($0) }
            )) {
                Text("开机自动启动")
                    .font(AnimalFont.body(13))
                    .foregroundStyle(AnimalPalette.textBody)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(AnimalPalette.primary)

            if launch.needsApproval {
                Text("还要在「系统设置 › 通用 › 登录项」里允许狸记额度才能生效。")
                    .font(AnimalFont.body(11))
                    .foregroundStyle(AnimalPalette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage = launch.errorMessage {
                Text(errorMessage)
                    .font(AnimalFont.body(11))
                    .foregroundStyle(AnimalPalette.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AnimalPalette.backgroundContent)
        .clipShape(RoundedRectangle(cornerRadius: AnimalRadius.card, style: .continuous))
    }

    private var visibilityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("显示的额度")
                .font(AnimalFont.heading(14))
                .foregroundStyle(AnimalPalette.textTitle)

            Text("关掉整个账号，或者只关掉其中某一份额度，关掉的部分不再展示。")
                .font(AnimalFont.body(11))
                .foregroundStyle(AnimalPalette.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(ProviderIdentifier.allCases, id: \.self) { provider in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ProviderIcon(provider: provider, color: AnimalPalette.textTitle)
                            .frame(width: 16, height: 16)
                        Text(provider.displayName)
                            .font(AnimalFont.body(13))
                            .foregroundStyle(AnimalPalette.textBody)
                        Spacer(minLength: 0)
                        Toggle("显示 \(provider.displayName)", isOn: providerBinding(for: provider))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .tint(AnimalPalette.primary)
                    }
                    .frame(height: 26)

                    ForEach(windows(of: provider), id: \.key) { item in
                        HStack(spacing: 8) {
                            Text(item.name)
                                .font(AnimalFont.body(12))
                                .foregroundStyle(AnimalPalette.textMuted)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Toggle("显示 \(provider.displayName) 的 \(item.name)", isOn: windowBinding(for: provider, key: item.key))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .tint(AnimalPalette.primary)
                                .disabled(!display.isVisible(provider))
                        }
                        .padding(.leading, 24)
                        .frame(height: 22)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AnimalPalette.backgroundContent)
        .clipShape(RoundedRectangle(cornerRadius: AnimalRadius.card, style: .continuous))
    }

    /// 当前已经读到的额度窗口；还没读到数据的账号只显示账号开关
    private func windows(of provider: ProviderIdentifier) -> [LimitWindowEntry] {
        model.providers.first { $0.provider == provider }?.orderedWindows ?? []
    }

    private func providerBinding(for provider: ProviderIdentifier) -> Binding<Bool> {
        Binding(
            get: { display.isVisible(provider) },
            set: { display.setVisible($0, for: provider) }
        )
    }

    private func windowBinding(for provider: ProviderIdentifier, key: String) -> Binding<Bool> {
        Binding(
            get: { display.isWindowVisible(key, for: provider) },
            set: { display.setWindowVisible($0, key: key, for: provider) }
        )
    }
}
