import SwiftUI

@main
@MainActor
struct RediscoverShuffleApp: App {
    @AppStorage(SettingsKeys.appearance) private var appearanceRawValue = AppAppearance.defaultValue.rawValue
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
                .tint(Color("AccentColor"))
                .preferredColorScheme(preferredColorScheme)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch AppAppearance.resolved(rawValue: appearanceRawValue) {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
