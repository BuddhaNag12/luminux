import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ProStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @Environment(AdConsent.self) private var adConsent
    @Environment(\.metro) private var metro
    @State private var showsTour = false
    @State private var showsBackgroundPicker = false
    @Environment(PhotoLibrary.self) private var library
    @Environment(HubTiles.self) private var hubTiles

    /// The six presets and the custom colour fit one row.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: Accent.presets.count + 1)

    @State private var page = 0

    /// Three short pivot pages instead of one long list: how it behaves, how it looks, and the rest.
    var body: some View {
        Pivot(overline: "LUMINUX · SETTINGS", selection: $page) {
            settingsPage { generalPage }.pivotTitle("general")
            settingsPage { lookPage }.pivotTitle("look")
            settingsPage { aboutPage }.pivotTitle("about")
        }
        .foregroundStyle(metro.foreground)
        .background(metro.background)
        .sheet(isPresented: $showsBackgroundPicker) {
            BackgroundPicker().environment(\.metro, metro)
        }
        .fullScreenCover(isPresented: $showsTour) {
            OnboardingView(isReplay: true) { showsTour = false }
        }
        .task {
            await store.refresh()
            if !store.isUnlocked { await adConsent.refreshPrivacyOptions() }
        }
    }

    private func settingsPage<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, MetroMetrics.margin + 12)
                .padding(.top, 24)
                .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private var lookPage: some View {
        @Bindable var settings = settings
        Text("theme").font(.metroBody)
            .metroFeather(row: 1)
            .padding(.bottom, 10)
        Segments(label: "theme", options: MetroTheme.allCases, selection: $settings.theme)
            .metroFeather(row: 1)
            .padding(.bottom, 24)

        HStack(alignment: .firstTextBaseline) {
            Text("accent colour").font(.metroBody)
            Spacer()
            Text(settings.accent.name).font(.metroCaption).foregroundStyle(metro.secondary)
        }
        .metroFeather(row: 2)
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
                                    .foregroundStyle(accent.onColor)
                            }
                        }
                }
                .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
                .metroFeather(row: 3, column: index)
                .accessibilityLabel(accent.name)
                .accessibilityAddTraits(settings.accent == accent ? .isSelected : [])
            }

            customAccentTile
                .metroFeather(row: 3, column: Accent.presets.count)
        }
        .padding(.bottom, 28)

        toggleRow("background photo", caption: "A photo behind the hub, picked each time Luminux opens.", isOn: $settings.showsHubBackground)
            .metroFeather(row: 4)
        if settings.showsHubBackground {
            link("background from", detail: BackgroundPicker.name(for: BackgroundPicker.current(settings, store: store), library: library, hubTiles: hubTiles)) {
                showsBackgroundPicker = true
            }
            .metroFeather(row: 5)
            .padding(.top, 20)
        }
    }

    @ViewBuilder private var generalPage: some View {
        @Bindable var settings = settings
        toggleRow("motion effect",
                  caption: "Tiles and the background shift as you tilt the phone. Off with Reduce Motion.",
                  isOn: $settings.movesWithPhone)
            .metroFeather(row: 1)
        if settings.movesWithPhone {
            Segments(label: "movement", options: TiltStrength.allCases, selection: $settings.tiltStrength)
                .metroFeather(row: 2)
                .padding(.top, 14)
        }
        Segments(label: "page animation", options: PageTransition.allCases, selection: $settings.pageTransition)
            .metroFeather(row: 3)
            .padding(.top, 32)
        toggleRow("live tiles",
                  caption: "Photo tiles flip to a new picture every few seconds. Off, they change each time you come back to the hub.",
                  isOn: $settings.animatesLiveTiles)
            .metroFeather(row: 3)
            .padding(.top, 32)
        toggleRow("tile patterns",
                  caption: "The albums and date tiles move slowly.",
                  isOn: $settings.animatesTilePatterns)
            .metroFeather(row: 4)
            .padding(.top, 32)
        Group {
            if store.unlocksPro {
                toggleRow("standby",
                          caption: "With the phone charging on its side, the small Photos widget shows three photos and today's date.",
                          isOn: $settings.showsStandBy)
            } else {
                link("standby", detail: "Photo tiles and the date on the small widget in StandBy. Comes with Luminux Pro.") {
                    navigator.push(.pro)
                }
            }
        }
            .metroFeather(row: 5)
            .padding(.top, 32)
        toggleRow("live photos",
                  caption: "Play their motion once when you open one.",
                  isOn: $settings.playsLivingImages)
            .metroFeather(row: 6)
            .padding(.top, 32)
        toggleRow("place names",
                  caption: "Titles journal trips like \"trip to goa\" and names places using Apple Maps. Only locations are sent, never photos.",
                  isOn: $settings.namesJournalPlaces)
            .metroFeather(row: 7)
            .padding(.top, 32)
    }

    @ViewBuilder private var aboutPage: some View {
        proCard
            .metroFeather(row: 1)
            .padding(.bottom, 28)
        VStack(alignment: .leading, spacing: 18) {
            if adConsent.needsPrivacyOptions && !store.isUnlocked {
                link("ad privacy choices", detail: "What Google may use to pick ads") {
                    Task { await adConsent.presentPrivacyOptions() }
                }
            }
            link("take the tour", detail: "What Luminux can do, page by page") { showsTour = true }
            link("about and licences", detail: "Version, fonts and their licences") { navigator.push(.about) }
            link("privacy policy", detail: "What Luminux and its ads collect") { openInApp(Self.privacyPolicyURL) }
            link("contact support", detail: "Questions, bugs and ideas on GitHub") { openInApp(Self.supportURL) }
            link("email support", detail: Self.supportEmail) { UIApplication.shared.open(Self.supportMailURL) }
        }
        .metroFeather(row: 2)
    }

    // The same pages go in App Store Connect's Privacy Policy and Support URL fields.
    private static let privacyPolicyURL = URL(string: "https://github.com/BuddhaNag12/luminux/blob/main/docs/privacy.md")!
    private static let supportURL = URL(string: "https://github.com/BuddhaNag12/luminux/issues")!
    private static let supportEmail = "buddhanag12@gmail.com"
    private static let supportMailURL = URL(string: "mailto:\(supportEmail)")!

    private func openInApp(_ url: URL) {
        UIApplication.shared.openInApp(url, tint: UIColor(metro.accentColor))
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
                            .foregroundStyle(metro.onAccent)
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
                        Text("LUMINUX PRO").font(.metroOverline).tracking(1.5).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
                .foregroundStyle(metro.onAccent)
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
                        .foregroundStyle(isCustom ? settings.accent.onColor : metro.foreground)
                }
        }
        .buttonStyle(TiltButtonStyle(touch: nil, size: .zero))
        .accessibilityLabel(isLocked ? "Custom colour, needs Luminux Pro" : "Custom colour")
        .accessibilityValue(isCustom ? settings.accent.name : "")
        .accessibilityAddTraits(isCustom ? .isSelected : [])
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
        // Every segment as tall as the tallest, so the dividers stay even.
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(MetroMotion.fade) { selection = option }
                } label: {
                    Text(option.rawValue)
                        .font(.metro(17, .semilight))
                        // A third of the width each: very large text shrinks to fit rather than breaking mid-word.
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 4)
                        .foregroundStyle(isSelected ? metro.onAccent : metro.foreground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minHeight: 44)
                        .background(isSelected ? metro.accentColor : metro.background)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: false, vertical: true)
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
