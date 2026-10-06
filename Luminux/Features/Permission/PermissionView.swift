import SwiftUI

struct PermissionView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(\.metro) private var metro

    private var isDenied: Bool { library.access == .denied }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LUMINUX")
                .font(.metroOverline)
                .tracking(1.5)
                .padding(.bottom, 4)

            Text("photos")
                .font(.metroPanorama)
                .lineLimit(1)
                .fixedSize()
                .padding(.leading, -6)

            Text(isDenied ? "access is off" : "your photos, front and centre")
                .font(.metroSection)
                .padding(.top, 8)

            Text(isDenied
                 ? "To browse your photos here, turn on photo access for Luminux in Settings."
                 : "Luminux shows the photos and videos already on this iPhone. Nothing leaves your device.")
                .font(.metroBody)
                .foregroundStyle(metro.secondary)
                .padding(.top, 12)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(isDenied ? "open settings" : "allow access") {
                if isDenied {
                    library.openSystemSettings()
                } else {
                    Task { await library.requestAccess() }
                }
            }
            .buttonStyle(.metro)
            .padding(.bottom, 24)
        }
        .foregroundStyle(metro.foreground)
        .padding(.horizontal, MetroMetrics.margin + 12)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(metro.background)
    }
}
