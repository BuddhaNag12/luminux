import SwiftUI

struct AppBarButton: Identifiable {
    /// Stays the same when the title flips (favorite/unfavorite), so the button updates in place.
    let id: String
    let title: String
    let systemImage: String
    var isEnabled = true
    let action: () -> Void

    init(id: String? = nil, title: String, systemImage: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.id = id ?? title
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
    }
}

struct AppBarMenuItem: Identifiable {
    let title: String
    var isEnabled = true
    let action: () -> Void

    var id: String { title }
}

/// Bottom bar of outlined circle buttons; "•••" reveals their labels and a text menu.
struct MetroAppBar: View {
    var buttons: [AppBarButton]
    var menuItems: [AppBarMenuItem] = []
    @Binding var isExpanded: Bool

    @Environment(\.metro) private var metro

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .top, spacing: 24) {
                    ForEach(buttons) { button in
                        Button {
                            collapse()
                            button.action()
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: button.systemImage)
                                    .font(.system(size: 18, weight: .light))
                                    .contentTransition(.symbolEffect(.replace))
                                    .symbolEffect(.bounce, value: button.systemImage)
                                    .animation(MetroMotion.snappy, value: button.systemImage)
                                    .frame(width: MetroMetrics.appBarButton, height: MetroMetrics.appBarButton)
                                if isExpanded {
                                    Text(button.title)
                                        .font(.metro(12))
                                        // As wide as its circle; VoiceOver users hear the full name anyway.
                                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                                        .lineLimit(1)
                                        .fixedSize()
                                        .contentTransition(.interpolate)
                                        // As wide as the circle, so a longer label doesn't push the other buttons aside.
                                        .frame(width: MetroMetrics.appBarButton)
                                        .transition(.opacity.combined(with: .offset(y: 6)))
                                }
                            }
                        }
                        .buttonStyle(CircleButtonStyle())
                        .disabled(!button.isEnabled)
                        .accessibilityLabel(button.title)
                    }
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity)

                Button {
                    withAnimation(MetroMotion.standard) { isExpanded.toggle() }
                } label: {
                    Text("•••")
                        .font(.metro(16, .semibold))
                        .frame(width: 56, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Less" : "More")
            }

            VStack(alignment: .leading, spacing: 0) {
                if isExpanded {
                    ForEach(Array(menuItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            collapse()
                            item.action()
                        } label: {
                            Text(item.title)
                                .font(.metro(20, .semilight))
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!item.isEnabled)
                        .opacity(item.isEnabled ? 1 : 0.4)
                        // Items rise in one after another, like the original menu; they leave together.
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 12))
                                .animation(MetroMotion.standard.delay(Double(index) * 0.02)),
                            removal: .opacity
                        ))
                    }
                }
            }
            .padding(.horizontal, MetroMetrics.margin + 12)
            .padding(.top, isExpanded && !menuItems.isEmpty ? 12 : 0)
            .padding(.bottom, isExpanded && !menuItems.isEmpty ? 8 : 0)
        }
        .frame(minHeight: MetroMetrics.appBarHeight, alignment: .top)
        .foregroundStyle(metro.foreground)
        .background((isExpanded ? metro.appBarExpanded : metro.appBar).ignoresSafeArea(edges: .bottom))
    }

    private func collapse() {
        guard isExpanded else { return }
        withAnimation(MetroMotion.standard) { isExpanded = false }
    }
}

/// Outlined circle that fills while pressed, inverting the glyph.
struct CircleButtonStyle: ButtonStyle {
    @Environment(\.metro) private var metro
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(metro.foreground)
            .background(alignment: .top) {
                Circle()
                    .fill(configuration.isPressed ? metro.foreground : .clear)
                    .strokeBorder(metro.foreground, lineWidth: 2)
                    .frame(width: MetroMetrics.appBarButton, height: MetroMetrics.appBarButton)
            }
            .overlay(alignment: .top) {
                if configuration.isPressed {
                    configuration.label
                        .foregroundStyle(metro.chrome)
                        .mask(alignment: .top) { Circle().frame(width: MetroMetrics.appBarButton, height: MetroMetrics.appBarButton) }
                }
            }
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .animation(MetroMotion.press, value: configuration.isPressed)
    }
}

extension View {
    /// Pins a `MetroAppBar` to the bottom. The expanded bar floats over the content; tapping outside collapses it.
    func metroAppBar(_ buttons: [AppBarButton], menu: [AppBarMenuItem] = [], isExpanded: Binding<Bool>) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: MetroMetrics.appBarHeight)
        }
        .overlay {
            if isExpanded.wrappedValue {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(MetroMotion.standard) { isExpanded.wrappedValue = false }
                    }
            }
        }
        .overlay(alignment: .bottom) {
            MetroAppBar(buttons: buttons, menuItems: menu, isExpanded: isExpanded)
        }
    }
}
