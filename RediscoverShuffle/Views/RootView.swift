import MediaPlayer
import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var playbackService: MusicPlaybackService
    @EnvironmentObject private var generatedQueueSession: GeneratedQueueSession

    var body: some View {
        Group {
            if libraryService.authorizationStatus == .authorized {
                NavigationStack {
                    PlaylistBrowserView()
                }
            } else {
                PermissionView()
            }
        }
        .task {
            libraryService.synchronizeAuthorizationAndLoad()
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
