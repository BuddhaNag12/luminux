import AVFoundation
import AVKit
import Photos
import SwiftUI

/// Plays the viewer's current video. The controls live in the viewer's app bar instead of the system player's overlay.
@Observable
final class VideoPlayback {
    private(set) var assetID: String?
    private(set) var player: AVPlayer?
    private(set) var isPlaying = false
    private(set) var isScrubbing = false
    private(set) var duration: Double = 0
    /// Updated about 30 times a second; only the scrubber row should read it.
    private(set) var currentTime: Double = 0
    var isMuted = false {
        didSet { player?.isMuted = isMuted }
    }

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var resumesAfterScrub = false

    /// Switches to `asset`, or stops playback when it's nil or not a video.
    func load(_ asset: PHAsset?) {
        let video = asset?.mediaType == .video ? asset : nil
        guard video?.localIdentifier != assetID else { return }
        unload()
        guard let video else { return }
        assetID = video.localIdentifier
        duration = video.duration
        loadTask = Task {
            guard let item = await ImageLoader.shared.playerItem(for: video), !Task.isCancelled else { return }
            attach(AVPlayer(playerItem: item), item: item)
        }
    }

    func togglePlay() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            // Plays sound with the ring/silent switch on, like the Photos app.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            player.play()
        }
        isPlaying.toggle()
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func scrub(to seconds: Double) {
        if !isScrubbing {
            isScrubbing = true
            resumesAfterScrub = isPlaying
            player?.pause()
        }
        seek(to: seconds, tolerance: CMTime(value: 1, timescale: 10))
    }

    func endScrub(at seconds: Double) {
        seek(to: seconds, tolerance: .zero)
        isScrubbing = false
        if resumesAfterScrub { player?.play() }
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds, tolerance: .zero)
    }

    private func seek(to seconds: Double, tolerance: CMTime) {
        currentTime = min(max(seconds, 0), duration)
        player?.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    private func attach(_ player: AVPlayer, item: AVPlayerItem) {
        player.isMuted = isMuted
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing else { return }
                self.currentTime = time.seconds
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Rewind and show the play button again, as the original did.
                self.isPlaying = false
                self.seek(to: 0, tolerance: .zero)
            }
        }
        self.player = player
    }

    private func unload() {
        loadTask?.cancel()
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player = nil
        assetID = nil
        isPlaying = false
        isScrubbing = false
        currentTime = 0
        duration = 0
    }
}

/// Bare video surface with no system controls.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerUIView { PlayerUIView() }

    func updateUIView(_ view: PlayerUIView, context: Context) {
        view.playerLayer.player = player
    }

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// Mute, elapsed and remaining time, a scrubber, and AirPlay; sits on top of the viewer's app bar.
struct VideoControlsRow: View {
    let playback: VideoPlayback

    @Environment(\.metro) private var metro

    var body: some View {
        HStack(spacing: 10) {
            Button {
                playback.isMuted.toggle()
            } label: {
                Image(systemName: playback.isMuted ? "speaker.slash" : "speaker.wave.2")
                    .font(.system(size: 16, weight: .light))
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playback.isMuted ? "Unmute" : "Mute")

            Text(Self.format(playback.currentTime))
                .monospacedDigit()
                .accessibilityHidden(true)
            MetroScrubber(playback: playback)
            Text("-" + Self.format((playback.duration - playback.currentTime).rounded(.up)))
                .monospacedDigit()
                .accessibilityHidden(true)

            AirPlayButton(tint: UIColor(metro.foreground), activeTint: UIColor(metro.accentColor))
                .frame(width: 32, height: 44)
                .accessibilityLabel("AirPlay")
        }
        .font(.metroCaption)
        .foregroundStyle(metro.foreground)
        .padding(.horizontal, MetroMetrics.margin + 4)
        .background(metro.chrome)
    }

    static func format(_ seconds: Double) -> String {
        Duration.seconds(max(seconds, 0).rounded(.down)).formatted(.time(pattern: .minuteSecond))
    }
}

/// Thin track with an accent fill and a square thumb; drag anywhere on it to scrub.
private struct MetroScrubber: View {
    let playback: VideoPlayback

    @Environment(\.metro) private var metro

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let progress = playback.duration > 0 ? min(max(playback.currentTime / playback.duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Rectangle().fill(metro.secondary.opacity(0.4)).frame(height: 2)
                Rectangle().fill(metro.accentColor).frame(width: width * progress, height: 2)
                Rectangle()
                    .fill(metro.foreground)
                    .frame(width: 4, height: playback.isScrubbing ? 20 : 14)
                    .offset(x: width * progress - 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { playback.scrub(to: seconds(at: $0.location.x, width: width)) }
                    .onEnded { playback.endScrub(at: seconds(at: $0.location.x, width: width)) }
            )
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(VideoControlsRow.format(playback.currentTime)) of \(VideoControlsRow.format(playback.duration))")
        .accessibilityAdjustableAction { direction in
            playback.skip(by: direction == .increment ? 5 : -5)
        }
    }

    private func seconds(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1)) * playback.duration
    }
}

private struct AirPlayButton: UIViewRepresentable {
    var tint: UIColor
    var activeTint: UIColor

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = tint
        view.activeTintColor = activeTint
    }
}
