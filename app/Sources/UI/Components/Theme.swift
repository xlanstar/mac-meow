import SwiftUI

enum Theme {
    static let orange = Color(red: 1.0, green: 0.58, blue: 0.30)
    static let pink = Color(red: 0.97, green: 0.36, blue: 0.49)
    static let accent = LinearGradient(colors: [orange, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let ok = Color(red: 0.20, green: 0.74, blue: 0.42)
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
