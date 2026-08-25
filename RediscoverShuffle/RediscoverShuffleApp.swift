import SwiftUI

@main
@MainActor
struct RediscoverShuffleApp: App {
    @StateObject private var libraryService = MusicLibraryService()
    @StateObject private var playbackService = MusicPlaybackService()
    @StateObject private var pinnedPlaylistStore = PinnedPlaylistStore()
    @StateObject private var generatedQueueSession = GeneratedQueueSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(libraryService)
                .environmentObject(playbackService)
                .environmentObject(pinnedPlaylistStore)
                .environmentObject(generatedQueueSession)
        }
    }
}
