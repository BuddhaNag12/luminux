import SwiftUI

/// The app version and the licence the bundled Selawik font ships under (the OFL asks for its text to go with it).
struct AboutView: View {
    @Environment(\.metro) private var metro

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "version \(short) (\(build))"
    }

    private var fontLicense: String {
        let text = Bundle.main.url(forResource: "Selawik-OFL", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        // The file is hard-wrapped at 70 columns; rejoin each paragraph so it wraps to the screen.
        return text
            .components(separatedBy: "\n\n")
            .map { paragraph in
                paragraph.split(separator: "\n")
                    .filter { !$0.allSatisfy { $0 == "-" } }
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("LUMINUX").font(.metroOverline).tracking(1.5)
                    .metroFeather(row: 0)
                Text("about")
                    .font(.metroTitle)
                    .padding(.leading, -3)
                    .metroFeather(row: 0)
                    .padding(.bottom, 16)

                Text(ProStore.isTestBuild ? "\(version) · test build, custom colours unlocked" : version)
                    .font(.metroBody)
                    .foregroundStyle(metro.secondary)
                    .metroFeather(row: 1)
                    .padding(.bottom, 28)

                Text("Selawik font")
                    .font(.metro(20, .semilight))
                    .foregroundStyle(metro.secondary)
                    .metroFeather(row: 2)
                    .padding(.bottom, 10)
                Text(fontLicense)
                    .font(.metroCaption)
                    .foregroundStyle(metro.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .metroFeather(row: 3)
            }
            .padding(.horizontal, MetroMetrics.margin + 12)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(metro.foreground)
        .background(metro.background)
    }
}
