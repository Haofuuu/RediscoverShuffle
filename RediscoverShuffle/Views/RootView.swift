import MediaPlayer
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var playbackService: MusicPlaybackService
    @EnvironmentObject private var generatedQueueSession: GeneratedQueueSession
    @EnvironmentObject private var playlistCoverStore: PlaylistCoverStore
    @State private var showsNowPlaying = false
    @State private var bottomSafeArea: CGFloat = 0
    @State private var isKeyboardVisible = false

    /// The system's floating bottom bars keep the same distance from the
    /// bottom edge as from the sides: 27pt on iPhones with a home indicator
    /// (7pt into the 34pt safe area), 16pt on those without one.
    private var floatingBarInset: CGFloat {
        max(16, bottomSafeArea - 7)
    }

    /// Sits the mini player inside the home-indicator zone rather than above
    /// it; a negative value lowers it past the bottom safe area.
    private var miniPlayerBottomPadding: CGFloat {
        floatingBarInset - bottomSafeArea
    }

    var body: some View {
        NavigationStack {
            if libraryService.authorizationStatus == .authorized {
                PlaylistBrowserView()
            } else {
                PermissionView()
            }
        }
        // Set on the screens only: the full player's own field keeps moving.
        .environment(\.isCoveredBySheet, showsNowPlaying)
        .floatingBottomBar {
            // Like the system's bottom bars, the mini player stays behind the
            // keyboard while search is being typed.
            if libraryService.authorizationStatus == .authorized,
               !isKeyboardVisible,
               let snapshot = playbackService.nowPlaying {
                MiniPlayerBar(snapshot: snapshot) {
                    showsNowPlaying = true
                }
                .padding(.horizontal, floatingBarInset)
                .padding(.bottom, miniPlayerBottomPadding)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
            }
        }
        .background {
            Color.clear
                .ignoresSafeArea(.keyboard)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.safeAreaInsets.bottom
                } action: { inset in
                    bottomSafeArea = inset
                }
        }
        // Animated through the state change rather than with `.animation` on
        // the whole screen, which would fight the keyboard's own motion.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.smooth(duration: 0.25)) {
                isKeyboardVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.smooth(duration: 0.25)) {
                isKeyboardVisible = false
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
            playlistCoverStore.reload(for: playlists)
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

private extension View {
    /// A bar pinned to the bottom of the screen. On iOS 26 and later, content
    /// scrolling beneath it fades under the system's scroll edge effect.
    @ViewBuilder
    func floatingBottomBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom, spacing: 0, content: content)
        } else {
            safeAreaInset(edge: .bottom, spacing: 0, content: content)
        }
    }
}
