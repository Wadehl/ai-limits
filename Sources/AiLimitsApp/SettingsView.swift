import SwiftUI
import AiLimitsCore
import AiLimitsUI

struct SettingsView: View {
    @ObservedObject var display: DisplaySettingsStore
    @StateObject private var launch = LaunchAtLogin()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RibbonTitle(text: "设置")
                .padding(.leading, 8)

            startupCard
            progressBarCard

            Text("进度条设置同时作用于菜单栏面板与桌面小组件。")
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

    private var progressBarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("进度条")
                .font(AnimalFont.heading(14))
                .foregroundStyle(AnimalPalette.textTitle)

            Text("关掉某个账号之后，它的额度只保留右侧的剩余百分比。")
                .font(AnimalFont.body(11))
                .foregroundStyle(AnimalPalette.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(ProviderIdentifier.allCases, id: \.self) { provider in
                HStack(spacing: 8) {
                    ProviderIcon(provider: provider, color: AnimalPalette.textTitle)
                        .frame(width: 16, height: 16)
                    Text(provider.displayName)
                        .font(AnimalFont.body(13))
                        .foregroundStyle(AnimalPalette.textBody)
                    Spacer(minLength: 0)
                    Toggle("显示 \(provider.displayName) 的进度条", isOn: progressBarBinding(for: provider))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(AnimalPalette.primary)
                }
                .frame(height: 26)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AnimalPalette.backgroundContent)
        .clipShape(RoundedRectangle(cornerRadius: AnimalRadius.card, style: .continuous))
    }

    private func progressBarBinding(for provider: ProviderIdentifier) -> Binding<Bool> {
        Binding(
            get: { display.showsProgressBar(for: provider) },
            set: { display.setShowsProgressBar($0, for: provider) }
        )
    }
}
