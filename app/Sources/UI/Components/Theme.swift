import SwiftUI

enum Theme {
    static let orange = Color(red: 1.0, green: 0.58, blue: 0.30)
    static let pink = Color(red: 0.97, green: 0.36, blue: 0.49)
    static let accent = LinearGradient(colors: [orange, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let ok = Color(red: 0.20, green: 0.74, blue: 0.42)

    static func color(_ tone: StatusSummary.Tone) -> Color {
        switch tone {
        case .accent: return orange
        case .ok: return ok
        case .error: return .red
        }
    }
}

/// 首頁的卡片外框。
struct Card: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.orange)
                    .opacity(isEnabled ? 1 : 0.55)
                    .shadow(color: Theme.orange.opacity(isEnabled ? 0.35 : 0), radius: 8, y: 3)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = .primary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06))
            )
            .contentShape(Rectangle())
    }
}
