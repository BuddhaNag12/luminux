import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ProStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @Environment(AdConsent.self) private var adConsent
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
                    Text(settings.accent.name).font(.metroCaption).foregroundStyle(metro.secondary)
                }
                .metroFeather(row: 3)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(Accent.presets.enumerated()), id: \.element) { index, accent in
                        Button {
                            withAnimation(MetroMotion.fade) { settings.accent = accent }
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
                        }
                        .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
                        .metroFeather(row: 4 + index / 4, column: index % 4)
                        .accessibilityLabel(accent.name)
                        .accessibilityAddTraits(settings.accent == accent ? .isSelected : [])
                    }

                    customAccentTile
                        .metroFeather(row: 4 + Accent.presets.count / 4, column: Accent.presets.count % 4)
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
                    if settings.movesWithPhone {
                        HStack(spacing: 12) {
                            ForEach(TiltStrength.allCases) { strength in
                                Button(strength.rawValue) {
                                    withAnimation(MetroMotion.fade) { settings.tiltStrength = strength }
                                }
                                .buttonStyle(.metro)
                                .overlay {
                                    if settings.tiltStrength == strength {
                                        Rectangle().strokeBorder(metro.accentColor, lineWidth: 2)
                                    }
                                }
                                .accessibilityLabel("\(strength.rawValue) movement")
                                .accessibilityAddTraits(settings.tiltStrength == strength ? .isSelected : [])
                            }
                        }
                        .padding(.top, 12)
                    }
                }
                .metroFeather(row: 11)
                .padding(.bottom, 20)
                Group {
                    Toggle("name places in the journal", isOn: $settings.namesJournalPlaces)
                        .toggleStyle(MetroToggleStyle())
                    Text("Asks Apple Maps where photos away from home were taken, for titles like \"trip to goa\". Only locations are sent, never photos.")
                        .font(.metroCaption)
                        .foregroundStyle(metro.secondary)
                        .padding(.top, 6)
                }
                .metroFeather(row: 12)
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
                .padding(.bottom, 28)

                if adConsent.needsPrivacyOptions && !store.isUnlocked {
                    Button("ad privacy choices") { Task { await adConsent.presentPrivacyOptions() } }
                        .buttonStyle(.metro)
                        .metroFeather(row: 14)
                        .padding(.bottom, 12)
                }

                Button("about and licences") { navigator.push(.about) }
                    .buttonStyle(.metro)
                    .metroFeather(row: 14)
            }
            .padding(.horizontal, MetroMetrics.margin + 12)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .foregroundStyle(metro.foreground)
        .background(metro.background)
        .task {
            if !store.isUnlocked { await adConsent.refreshPrivacyOptions() }
        }
    }

    /// Opens the colour picker for any accent; shows the custom colour once one is picked.
    private var customAccentTile: some View {
        let isCustom = !settings.accent.isPreset
        let isLocked = !store.unlocksCustomAccent
        return Button {
            if isLocked {
                navigator.push(.pro)
            } else {
                AccentColorPicker.present(initial: settings.accent) { settings.accent = $0 }
            }
        } label: {
            (isCustom ? settings.accent.color : metro.chrome)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if isCustom {
                        Rectangle().strokeBorder(metro.foreground, lineWidth: 3)
                    }
                    Image(systemName: "eyedropper")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(isCustom ? .white : metro.foreground)
                }
                .overlay(alignment: .bottomTrailing) {
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(metro.foreground.opacity(0.85))
                            .padding(6)
                    }
                }
        }
        .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
        .accessibilityLabel(isLocked ? "Custom colour, needs Luminux Pro" : "Custom colour")
        .accessibilityValue(isCustom ? settings.accent.name : "")
        .accessibilityAddTraits(isCustom ? .isSelected : [])
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

/// The system colour picker without opacity. It reports every change, so the app's accent follows the drag.
/// UIKit presents it directly: its "pick from screen" hides the picker and then re-presents it, which crashes when
/// it's wrapped in a SwiftUI sheet (there's no presented controller to bring back).
enum AccentColorPicker {
    /// The picker holds its delegate weakly; this keeps the open one alive.
    private static var activeDelegate: Delegate?

    static func present(initial: Accent, onChange: @escaping (Accent) -> Void) {
        guard let presenter = UIApplication.shared.topViewController else { return }
        let picker = UIColorPickerViewController()
        picker.supportsAlpha = false
        picker.selectedColor = UIColor(initial.color)
        let delegate = Delegate(onChange: onChange)
        activeDelegate = delegate
        picker.delegate = delegate
        picker.sheetPresentationController?.detents = [.medium(), .large()]
        presenter.present(picker, animated: true)
    }

    private final class Delegate: NSObject, UIColorPickerViewControllerDelegate {
        let onChange: (Accent) -> Void

        init(onChange: @escaping (Accent) -> Void) { self.onChange = onChange }

        func colorPickerViewController(_ picker: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
            // Display P3 picks can fall outside sRGB.
            let clamp = { (value: CGFloat) in Double(min(max(value, 0), 1)) }
            onChange(.custom(red: clamp(red), green: clamp(green), blue: clamp(blue)))
        }

        func colorPickerViewControllerDidFinish(_ picker: UIColorPickerViewController) {
            AccentColorPicker.activeDelegate = nil
        }
    }
}
