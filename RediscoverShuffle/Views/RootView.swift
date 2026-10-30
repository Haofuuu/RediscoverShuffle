import MediaPlayer
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var playbackService: MusicPlaybackService
    @EnvironmentObject private var generatedQueueSession: GeneratedQueueSession
    @State private var showsNowPlaying = false

    var body: some View {
        NavigationStack {
            if libraryService.authorizationStatus == .authorized {
                PlaylistBrowserView()
            } else {
                PermissionView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if libraryService.authorizationStatus == .authorized,
               let snapshot = playbackService.nowPlaying {
                MiniPlayerBar(snapshot: snapshot) {
                    showsNowPlaying = true
                }
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
            }
        }
        .animation(.smooth(duration: 0.3), value: playbackService.nowPlaying == nil)
        .sheet(isPresented: $showsNowPlaying) {
            NowPlayingSheet()
        }
        .task {
            libraryService.synchronizeAuthorizationAndLoad()
        }
        .onReceive(libraryService.$authorizationStatus) { status in
            if status == .authorized {
                playbackService.synchronizePlayerState()
            }
        }
        .onReceive(libraryService.$playlists) { playlists in
            guard let restoration = generatedQueueSession.restoreIfNeeded(from: playlists) else {
                return
            }

            if generatedQueueSession.shouldRestorePlaybackTracking(
                for: restoration.viewModel.queueID
            ) {
                playbackService.restoreQueueTracking(
                    queueID: restoration.viewModel.queueID,
                    mappings: restoration.playbackIndexMappings
                )
            }
        }
        .onReceive(playbackService.$generatedQueueProgress) { progress in
            guard let progress else {
                return
            }
            generatedQueueSession.updatePlaybackProgress(progress)
        }
        .onReceive(playbackService.$generatedQueueInvalidationID) { queueID in
            guard let queueID else {
                return
            }
            generatedQueueSession.invalidatePlaybackTracking(for: queueID)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            libraryService.synchronizeAuthorizationAndLoad()
            playbackService.synchronizePlayerState()
        }
    }
}
