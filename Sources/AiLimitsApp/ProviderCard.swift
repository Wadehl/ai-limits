import SwiftUI
import AiLimitsCore
import AiLimitsUI

struct ProviderCard: View {
    let limits: ProviderLimits

    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if limits.status == .ok {
                ForEach(limits.orderedWindows, id: \.key) { item in
                    windowRow(name: item.name, window: item.window)
                }
            } else if let message = limits.error {
                Text(message)
                    .font(AnimalFont.body(12))
                    .foregroundStyle(limits.status == .error ? AnimalPalette.error : AnimalPalette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AnimalPalette.backgroundContent)
        .clipShape(RoundedRectangle(cornerRadius: AnimalRadius.card, style: .continuous))
        .offset(y: hovered ? -2 : 0)
        .animation(AnimalMotion.ease, value: hovered)
        .onHover { hovered = $0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ProviderIcon(provider: limits.provider, color: AnimalPalette.textTitle)
                .frame(width: 16, height: 16)
            Text(limits.provider.displayName)
                .font(AnimalFont.heading(15))
                .foregroundStyle(AnimalPalette.textTitle)
            if let plan = limits.planType {
                AnimalTag(text: plan, tinted: true)
            }
            Spacer(minLength: 0)
            if let account = limits.accountLabel {
                Text(account)
                    .font(AnimalFont.body(11))
                    .foregroundStyle(AnimalPalette.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func windowRow(name: String, window: RateLimitWindow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(name)
                    .font(AnimalFont.body(12))
                    .foregroundStyle(AnimalPalette.textMuted)
                Spacer(minLength: 0)
                if let reset = window.resetDescription {
                    Text("重置于 \(reset)")
                        .font(AnimalFont.body(11))
                        .foregroundStyle(AnimalPalette.textDisabled)
                }
            }
            LimitBar(remainingPercent: window.remainingPercent)
        }
    }
}
