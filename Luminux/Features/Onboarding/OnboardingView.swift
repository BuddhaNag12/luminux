import SwiftUI

/// The first-launch tour: what Luminux does, one feature per page, ending with photo access. Shown once; settings can
/// replay it, and then the last page just closes it.
struct OnboardingView: View {
    /// True when replayed from settings: no access request at the end.
    var isReplay = false
    var onFinish: () -> Void

    @Environment(PhotoLibrary.self) private var library
    @Environment(\.metro) private var metro
    @State private var page = 0

    private var pages: [OnboardingPage] { OnboardingPage.all }
    private var isLast: Bool { page == pages.count - 1 }

    #if DEBUG
    /// `-onboarding` shows the tour on every launch, for checking it.
    static var isForced: Bool { ProcessInfo.processInfo.arguments.contains("-onboarding") }
    #else
    static var isForced: Bool { false }
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("LUMINUX").font(.metroOverline).tracking(1.5)
                    .frame(minHeight: 44)
                Spacer()
                if !isLast {
                    Button("skip") { withAnimation(MetroMotion.standard) { page = pages.count - 1 } }
                        .font(.metro(17, .semilight))
                        .foregroundStyle(metro.secondary)
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .accessibilityHint("Goes to the last page")
                }
            }
            .padding(.horizontal, MetroMetrics.margin + 12)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    OnboardingPageView(page: pages[index], isCurrent: index == page, asksForAccess: !isReplay && !library.access.canRead)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            footer
                .padding(.horizontal, MetroMetrics.margin + 12)
                .padding(.bottom, 16)
        }
        .padding(.top, 8)
        .foregroundStyle(metro.foreground)
        .background(metro.background)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Square page markers, the current one filled with the accent.
            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { index in
                    Rectangle()
                        .fill(index == page ? metro.accentColor : metro.foreground.opacity(0.25))
                        .frame(width: index == page ? 18 : 8, height: 8)
                }
            }
            .animation(MetroMotion.snappy, value: page)
            .accessibilityElement()
            .accessibilityLabel("Page \(page + 1) of \(pages.count)")

            HStack(spacing: 12) {
                if page > 0 {
                    Button("back") { withAnimation(MetroMotion.standard) { page -= 1 } }
                        .buttonStyle(.metro)
                }
                Spacer(minLength: 0)
                primaryButton
            }
        }
    }

    @ViewBuilder private var primaryButton: some View {
        if !isLast {
            Button("next") { withAnimation(MetroMotion.standard) { page += 1 } }
                .buttonStyle(.metro)
        } else if isReplay || library.access.canRead {
            Button(isReplay ? "done" : "get started", action: onFinish)
                .buttonStyle(.metro)
        } else if library.access == .denied {
            Button("open settings") { library.openSystemSettings() }
                .buttonStyle(.metro)
        } else {
            Button("allow access") {
                Task {
                    await library.requestAccess()
                    onFinish()
                }
            }
            .buttonStyle(.metro)
        }
    }
}

struct OnboardingPage: Identifiable {
    enum Visual { case logo, glyph(String) }

    let id: String
    let visual: Visual
    let title: String
    let body: String
    /// What needs Pro on this page, if anything.
    var pro: String?
    /// Added to the body while photo access hasn't been given yet.
    var accessNote: String?

    static let all: [OnboardingPage] = [
        OnboardingPage(
            id: "welcome", visual: .logo,
            title: "your photos, front and centre",
            body: "A tile-based home for the photos and videos already on your iPhone."
        ),
        OnboardingPage(
            id: "browse", visual: .glyph("square.stack.3d.up"),
            title: "browse your way",
            body: "Pin albums to a hub of live tiles, pinch the grid for bigger or smaller photos, and relive your days and trips in the journal.",
            pro: "Two pins are free; Pro pins as many as you like."
        ),
        OnboardingPage(
            id: "create", visual: .glyph("slider.horizontal.3"),
            title: "make it yours",
            body: "Edit with crop, light, colour and one-tap looks, lift a person or pet out of a photo, and put any collection on your Home Screen as a widget.",
            pro: "Editing and lifting come with Pro, or watch a short ad to use them once. The small widget is free."
        ),
        OnboardingPage(
            id: "privacy", visual: .glyph("lock"),
            title: "your photos stay yours",
            body: "Luminux shows the photos already on this iPhone, and they never leave it. Journal place names come from Apple Maps, which gets locations only.",
            accessNote: "To begin, allow access to your photo library."
        ),
    ]
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let isCurrent: Bool
    var asksForAccess = false

    @Environment(\.metro) private var metro
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilesIn = [false, false, false]
    @State private var showsText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 12)
            visual
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 12) {
                Text(page.title)
                    .font(.metro(38, .light, relativeTo: .largeTitle))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(asksForAccess ? [page.body, page.accessNote].compactMap { $0 }.joined(separator: " ") : page.body)
                    .font(.metroBody)
                    .foregroundStyle(metro.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let pro = page.pro {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("PRO")
                            .font(.metroOverline)
                            .tracking(1.2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(metro.accentColor)
                        Text(pro)
                            .font(.metroCaption)
                            .foregroundStyle(metro.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                    .accessibilityElement(children: .combine)
                }
            }
            .offset(x: showsText || reduceMotion ? 0 : 24)
            .opacity(showsText || reduceMotion ? 1 : 0)
            Spacer(minLength: 24)
        }
        .padding(.horizontal, MetroMetrics.margin + 12)
        .task(id: isCurrent) { await enter() }
    }

    @ViewBuilder private var visual: some View {
        switch page.visual {
        case .logo:
            LogoLockup(unit: 1.1, cutout: metro.background)
        case .glyph(let name):
            GlyphStack(symbol: name, tilesIn: reduceMotion ? [true, true, true] : tilesIn)
        }
    }

    /// The tiles stack in and the text slides in each time the page comes into view.
    private func enter() async {
        guard isCurrent, !reduceMotion else { return }
        tilesIn = [false, false, false]
        showsText = false
        for index in 0..<3 {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { tilesIn[index] = true }
            try? await Task.sleep(for: .milliseconds(80))
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { showsText = true }
    }
}

/// The logo's stacked tiles with a feature glyph on the front one, so every page looks like part of the same family.
private struct GlyphStack: View {
    let symbol: String
    var tilesIn: [Bool]

    @Environment(\.metro) private var metro

    private static let side: CGFloat = 132
    private static let step: CGFloat = 24
    private static let opacities = [0.35, 0.65, 1.0]

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ForEach(0..<3, id: \.self) { index in
                let back = CGFloat(2 - index)
                Rectangle()
                    .fill(metro.accentColor.opacity(Self.opacities[index]))
                    .frame(width: Self.side, height: Self.side)
                    .overlay {
                        if index == 2 {
                            Image(systemName: symbol)
                                .font(.system(size: 52, weight: .ultraLight))
                                .foregroundStyle(.white)
                        }
                    }
                    .offset(x: back * Self.step, y: -back * Self.step)
                    .offset(y: tilesIn[index] ? 0 : 60)
                    .opacity(tilesIn[index] ? 1 : 0)
            }
        }
        .frame(width: Self.side + 2 * Self.step, height: Self.side + 2 * Self.step, alignment: .bottomLeading)
    }
}
