import SwiftUI

/// An album or a handful of photos to pin to the hub's collection panel.
struct PinRequest: Identifiable {
    enum Target {
        case album(String)
        case photos([String])
    }

    let id = UUID()
    let target: Target
    /// Runs once the tile is pinned, e.g. to leave select mode.
    var onPinned: () -> Void = {}
}

extension View {
    /// Pins what `request` asks for: an album straight away, photos once they have a name. Past the free limit it
    /// explains the limit and offers Pro instead.
    func hubPinning(_ request: Binding<PinRequest?>) -> some View {
        modifier(HubPinning(request: request))
    }
}

private struct HubPinning: ViewModifier {
    @Binding var request: PinRequest?

    @Environment(HubTiles.self) private var hubTiles
    @Environment(ProStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var pendingPhotos: PinRequest?
    @State private var isNaming = false
    @State private var name = ""
    @State private var showsLimit = false

    func body(content: Content) -> some View {
        content
            .onChange(of: request?.id) { _, id in
                guard id != nil, let pending = request else { return }
                request = nil
                handle(pending)
            }
            .alert("Pin to collection", isPresented: $isNaming) {
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button("Pin") {
                    guard let pending = pendingPhotos, case .photos(let ids) = pending.target else { return }
                    withAnimation(MetroMotion.standard) { hubTiles.pinPhotoSet(title: name, photoIDs: ids) }
                    pending.onPinned()
                }
            } message: {
                Text("The photos show up together as a live tile on the hub.")
            }
            .alert("Free pins used", isPresented: $showsLimit) {
                Button("See Pro") { navigator.push(.pro) }
                Button("OK", role: .cancel) {}
            } message: {
                Text("You can pin \(HubTiles.freePinLimit) albums or photo sets for free. Unpin one from the hub, or unlock Pro to pin as many as you like.")
            }
    }

    private func handle(_ pending: PinRequest) {
        guard hubTiles.canPin(isPro: store.isUnlocked) else {
            showsLimit = true
            return
        }
        switch pending.target {
        case .album(let id):
            hubTiles.pinAlbum(id)
            pending.onPinned()
        case .photos:
            name = ""
            pendingPhotos = pending
            isNaming = true
        }
    }
}
