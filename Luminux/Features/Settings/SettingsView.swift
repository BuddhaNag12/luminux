import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ProStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @Environment(AdConsent.self) private var adConsent
    @Environment(\.metro) private var metro

    /// The six presets and the custom colour fit one row.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: Accent.presets.count + 1)

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
                    .padding(.bottom, 20)

                proCard
                    .metroFeather(row: 1)

                section("appearance")
                    .metroFeather(row: 2)
                Segments(label: "background", options: MetroTheme.allCases, selection: $settings.theme)
                    .metroFeather(row: 3)
                    .padding(.bottom, 20)

                HStack(alignment: .firstTextBaseline) {
                    Text("accent colour").font(.metroBody)
                    Spacer()
                    Text(settings.accent.name).font(.metroCaption).foregroundStyle(metro.secondary)
                }
                .metroFeather(row: 4)
                .padding(.bottom, 10)
                LazyVGrid(columns: columns, spacing: 6) {
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
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
                        .metroFeather(row: 5, column: index)
                        .accessibilityLabel(accent.name)
                        .accessibilityAddTraits(settings.accent == accent ? .isSelected : [])
                    }

                    customAccentTile
                        .metroFeather(row: 5, column: Accent.presets.count)
                }

                section("hub")
                    .metroFeather(row: 6)
                toggleRow("background photo", isOn: $settings.showsHubBackground)
                    .metroFeather(row: 7)
                    .padding(.bottom, 20)
                toggleRow("motion effect",
                          caption: "Tiles and the background shift as you tilt the phone. Off with Reduce Motion.",
                          isOn: $settings.movesWithPhone)
                    .metroFeather(row: 8)
                if settings.movesWithPhone {
                    Segments(label: "movement", options: TiltStrength.allCases, selection: $settings.tiltStrength)
                        .metroFeather(row: 9)
                        .padding(.top, 14)
                }

                section("photos")
                    .metroFeather(row: 10)
                toggleRow("live photos",
                          caption: "Play their motion once when you open one.",
                          isOn: $settings.playsLivingImages)
                    .metroFeather(row: 11)
                    .padding(.bottom, 20)
                toggleRow("place names",
                          caption: "Titles journal trips like \"trip to goa\" using Apple Maps. Only locations are sent, never photos.",
                          isOn: $settings.namesJournalPlaces)
                    .metroFeather(row: 12)

                section("more")
                    .metroFeather(row: 13)
                VStack(alignment: .leading, spacing: 18) {
                    if adConsent.needsPrivacyOptions && !store.isUnlocked {
                        link("ad privacy choices", detail: "What Google may use to pick ads") {
                            Task { await adConsent.presentPrivacyOptions() }
                        }
                    }
                    link("about and licences", detail: "Version, fonts and their licences") { navigator.push(.about) }
                }
                .metroFeather(row: 14)
            }
            .padding(.horizontal, MetroMetrics.margin + 12)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .foregroundStyle(metro.foreground)
        .background(metro.background)
        .task {
            await store.refresh()
            if !store.isUnlocked { await adConsent.refreshPrivacyOptions() }
        }
    }

    /// An accent tile that opens the Pro page, or a quiet thank-you once it's bought.
    @ViewBuilder private var proCard: some View {
        if store.isUnlocked {
            HStack(spacing: 14) {
                metro.accentColor
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(.white)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("pro unlocked").font(.metro(20, .semilight))
                    Text("Thank you for supporting Luminux.")
                        .font(.metroCaption)
                        .foregroundStyle(metro.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(metro.chrome)
            .accessibilityElement(children: .combine)
        } else {
            Button { navigator.push(.pro) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("LUMINUX PRO").font(.metroOverline).tracking(1.5)
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 18, weight: .light))
                    }
                    Text("no ads, more of you")
                        .font(.metroSection)
                        .padding(.top, 14)
                    Text("Any accent colour, wide live tiles, unlimited pins, slideshow and editing.")
                        .font(.metroCaption)
                        .opacity(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                    Text(store.product.map { "\($0.displayPrice), once. No subscription." } ?? "One payment. No subscription.")
                        .font(.metro(15, .semibold))
                        .padding(.top, 16)
                }
                .foregroundStyle(.white)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(metro.accentColor)
                .contentShape(Rectangle())
            }
            .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
            .accessibilityLabel("Luminux Pro")
            .accessibilityHint("Shows what Pro adds and its price")
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
                    Image(systemName: isLocked ? "lock.fill" : "eyedropper")
                        .font(.system(size: isLocked ? 13 : 17, weight: .light))
                        .foregroundStyle(isCustom ? .white : metro.foreground)
                }
        }
        .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
        .accessibilityLabel(isLocked ? "Custom colour, needs Luminux Pro" : "Custom colour")
        .accessibilityValue(isCustom ? settings.accent.name : "")
        .accessibilityAddTraits(isCustom ? .isSelected : [])
    }

    private func section(_ text: String) -> some View {
        Text(text)
            .font(.metro(22, .semilight))
            // Not the accent: cobalt and other dark accents are too dim for text on black.
            .foregroundStyle(metro.secondary)
            .padding(.top, 36)
            .padding(.bottom, 14)
            .accessibilityAddTraits(.isHeader)
    }

    private func toggleRow(_ title: String, caption: String? = nil, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.metroBody)
                if let caption {
                    Text(caption)
                        .font(.metroCaption)
                        .foregroundStyle(metro.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(MetroToggleStyle())
    }

    private func link(_ title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.metro(20, .semilight))
                Text(detail).font(.metroCaption).foregroundStyle(metro.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Equal-width choices in one outlined bar; the chosen one fills with the accent.
private struct Segments<Option: CaseIterable & Identifiable & RawRepresentable<String>>: View where Option.AllCases: RandomAccessCollection {
    let label: String
    let options: Option.AllCases
    @Binding var selection: Option

    @Environment(\.metro) private var metro

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(MetroMotion.fade) { selection = option }
                } label: {
                    Text(option.rawValue)
                        .font(.metro(17, .semilight))
                        .foregroundStyle(isSelected ? .white : metro.foreground)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isSelected ? metro.accentColor : metro.background)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        // The gaps between segments show this colour as dividers.
        .padding(2)
        .background(metro.foreground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// Label on the left, a rectangular track with a square thumb on the right.
struct MetroToggleStyle: ToggleStyle {
    @Environment(\.metro) private var metro

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(MetroMotion.snappy) { configuration.isOn.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 16) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Rectangle()
                        .fill(configuration.isOn ? metro.accentColor : .clear)
                        .strokeBorder(configuration.isOn ? metro.accentColor : metro.foreground, lineWidth: 2)
                        .frame(width: 52, height: 24)
                    Rectangle()
                        .fill(metro.foreground)
                        .frame(width: 12, height: 24)
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
