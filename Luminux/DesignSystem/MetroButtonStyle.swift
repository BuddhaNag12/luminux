import SwiftUI

/// Outlined rectangular button; fills with the accent color while pressed.
struct MetroButtonStyle: ButtonStyle {
    @Environment(\.metro) private var metro

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.metro(17, .semilight))
            .foregroundStyle(configuration.isPressed ? .white : metro.foreground)
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
            .background(configuration.isPressed ? metro.accentColor : .clear)
            .overlay(Rectangle().strokeBorder(configuration.isPressed ? metro.accentColor : metro.foreground, lineWidth: 2))
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == MetroButtonStyle {
    static var metro: MetroButtonStyle { MetroButtonStyle() }
}
