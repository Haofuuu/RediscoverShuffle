import Combine
import Foundation
import MediaPlayer

@MainActor
final class MusicPlaybackService: ObservableObject {
    @Published private(set) var nowPlaying = NowPlayingSnapshot.empty
    @Published private(set) var playbackState: MPMusicPlaybackState = .stopped
    @Published private(set) var isPreparing = false
    @Published var errorMessage: String?

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var notificationObservers: [NSObjectProtocol] = []

    init() {
        player.beginGeneratingPlaybackNotifications()

        let center = NotificationCenter.default
        notificationObservers.append(center.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshPlayerState() }
        })
        notificationObservers.append(center.addObserver(
            forName: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshPlayerState() }
        })

        refreshPlayerState()
    }

    deinit {
        let center = NotificationCenter.default
        notificationObservers.forEach(center.removeObserver)
        player.endGeneratingPlaybackNotifications()
    }

    func setQueueAndPlay(entries: [PlaylistEntry]) {
        guard !entries.isEmpty else {
            errorMessage = "This playlist has no songs to play."
            return
        }

        isPreparing = true
        errorMessage = nil
        player.shuffleMode = .off
        player.repeatMode = .none
        player.setQueue(with: MPMediaItemCollection(items: entries.map(\.mediaItem)))

        player.prepareToPlay { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isPreparing = false
                if let error {
                    self.errorMessage = "The Music app could not prepare this queue. One or more songs may be unavailable. \(error.localizedDescription)"
                    self.refreshPlayerState()
                    return
                }
                self.player.play()
                self.refreshPlayerState()
            }
        }
    }

    /// MediaPlayer does not expose a per-item preparation error. This action
    /// lets the listener move past an unavailable item without rebuilding the
    /// rest of the generated queue.
    func skipUnavailableItemAndContinue() {
        errorMessage = nil
        player.skipToNextItem()
        player.play()
        refreshPlayerState()
    }

    var playbackStateDescription: String {
        switch playbackState {
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        case .interrupted: return "Interrupted"
        case .seekingForward: return "Seeking forward"
        case .seekingBackward: return "Seeking backward"
        @unknown default: return "Playback state unavailable"
        }
    }

    private func refreshPlayerState() {
        playbackState = player.playbackState
        guard let item = player.nowPlayingItem else {
            nowPlaying = .empty
            return
        }

        nowPlaying = NowPlayingSnapshot(
            title: safeText(item.title, fallback: "Unknown Title"),
            artist: safeText(item.artist, fallback: "Unknown Artist"),
            artwork: item.artwork
        )
    }

    private func safeText(_ value: String?, fallback: String) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        return value
    }
}
