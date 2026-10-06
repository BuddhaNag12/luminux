import SwiftUI

struct AppBarButton: Identifiable {
    let title: String
    let systemImage: String
    var isEnabled = true
    let action: () -> Void

    var id: String { title }
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
                                    .frame(width: MetroMetrics.appBarButton, height: MetroMetrics.appBarButton)
                                if isExpanded {
                                    Text(button.title)
                                        .font(.metro(12))
                                        .lineLimit(1)
                                        .fixedSize()
                                        .transition(.opacity)
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

            if isExpanded && !menuItems.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(menuItems) { item in
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
                    }
                }
                .padding(.horizontal, MetroMetrics.margin + 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minHeight: MetroMetrics.appBarHeight, alignment: .top)
        .foregroundStyle(metro.foreground)
        .background(metro.chrome.ignoresSafeArea(edges: .bottom))
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
