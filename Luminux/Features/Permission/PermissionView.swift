import SwiftUI

struct PermissionView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(\.metro) private var metro

    private var isDenied: Bool { library.access == .denied }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LogoLockup(unit: 1, cutout: metro.background)
                .padding(.top, 24)

            Text(isDenied ? "access is off" : "your photos, front and centre")
                .font(.metroSection)
                .padding(.top, 32)

            Text(isDenied
                 ? "To browse your photos here, turn on photo access for Luminux in Settings."
                 : "Luminux shows the photos and videos already on this iPhone. Your photos never leave it; only to name places in your journal does it ask Apple Maps about photo locations, and you can turn that off in settings.")
                .font(.metroBody)
                .foregroundStyle(metro.secondary)
                .padding(.top, 12)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(isDenied ? "open settings" : "continue") {
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
