import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ProStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @Environment(\.metro) private var metro

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("LUMINUX").font(.metroOverline).tracking(1.5)
                    .metroFeather(row: 0)
                Text("settings")
                    .font(.metroTitle)
                    .padding(.leading, -3)
                    .metroFeather(row: 0)
                    .padding(.bottom, 16)

                label("background")
                    .metroFeather(row: 1)
                HStack(spacing: 12) {
                    ForEach(MetroTheme.allCases) { theme in
                        Button(theme.rawValue) {
                            withAnimation(MetroMotion.fade) { settings.theme = theme }
                        }
                        .buttonStyle(.metro)
                        .overlay {
                            if settings.theme == theme {
                                Rectangle().strokeBorder(metro.accentColor, lineWidth: 2)
                            }
                        }
                        .accessibilityAddTraits(settings.theme == theme ? .isSelected : [])
                    }
                }
                .metroFeather(row: 2)
                .padding(.bottom, 28)

                HStack(alignment: .firstTextBaseline) {
                    label("accent color")
                    Spacer()
                    Text(settings.accent.rawValue).font(.metroCaption).foregroundStyle(metro.secondary)
                }
                .metroFeather(row: 3)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(Accent.allCases.enumerated()), id: \.element) { index, accent in
                        let isLocked = !accent.isFree && !store.isUnlocked
                        Button {
                            if isLocked {
                                navigator.push(.pro)
                            } else {
                                withAnimation(MetroMotion.fade) { settings.accent = accent }
                            }
                        } label: {
                            accent.color
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    if settings.accent == accent {
                                        Rectangle().strokeBorder(metro.foreground, lineWidth: 3)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .overlay(alignment: .bottomTrailing) {
                                    if isLocked {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.85))
                                            .padding(6)
                                    }
                                }
                        }
                        .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
                        .metroFeather(row: 4 + index / 4, column: index % 4)
                        .accessibilityLabel(isLocked ? "\(accent.rawValue), needs Luminux Pro" : accent.rawValue)
                        .accessibilityAddTraits(settings.accent == accent ? .isSelected : [])
                    }
                }
                .padding(.bottom, 28)

                Toggle("show a photo behind the hub", isOn: $settings.showsHubBackground)
                    .toggleStyle(MetroToggleStyle())
                    .metroFeather(row: 9)
                    .padding(.bottom, 20)
                Group {
                    Toggle("play living images", isOn: $settings.playsLivingImages)
                        .toggleStyle(MetroToggleStyle())
                    Text("Live Photos play their motion once when you open them.")
                        .font(.metroCaption)
                        .foregroundStyle(metro.secondary)
                        .padding(.top, 6)
                }
                .metroFeather(row: 10)
                .padding(.bottom, 20)
                Group {
                    Toggle("move the hub with the phone", isOn: $settings.movesWithPhone)
                        .toggleStyle(MetroToggleStyle())
                    Text("The background photo and tiles shift a little as you tilt the phone. Off when Reduce Motion is on.")
                        .font(.metroCaption)
                        .foregroundStyle(metro.secondary)
                        .padding(.top, 6)
                }
                .metroFeather(row: 11)
                .padding(.bottom, 28)

                label("luminux pro")
                    .metroFeather(row: 12)
                Group {
                    if store.isUnlocked {
                        Text("Unlocked. Thank you for supporting Luminux.")
                            .font(.metroBody)
                    } else {
                        Button("see what pro adds") { navigator.push(.pro) }
                            .buttonStyle(.metro)
                    }
                }
                .metroFeather(row: 13)
            }
            .padding(.horizontal, MetroMetrics.margin + 12)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .foregroundStyle(metro.foreground)
        .background(metro.background)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.metro(20, .semilight))
            .foregroundStyle(metro.secondary)
            .padding(.bottom, 10)
    }
}

/// Rectangular track with a square thumb, "on"/"off" beside it.
struct MetroToggleStyle: ToggleStyle {
    @Environment(\.metro) private var metro

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(MetroMotion.snappy) { configuration.isOn.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                configuration.label.font(.metroBody)
                HStack(spacing: 12) {
                    ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                        Rectangle()
                            .fill(configuration.isOn ? metro.accentColor : .clear)
                            .strokeBorder(configuration.isOn ? metro.accentColor : metro.foreground, lineWidth: 2)
                            .frame(width: 56, height: 24)
                        Rectangle()
                            .fill(metro.foreground)
                            .frame(width: 12, height: 24)
                    }
                    Text(configuration.isOn ? "on" : "off").font(.metroBody)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}
