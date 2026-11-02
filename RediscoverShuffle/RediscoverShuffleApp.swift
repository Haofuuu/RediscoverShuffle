import SwiftUI
import UIKit

@main
@MainActor
struct RediscoverShuffleApp: App {
    @AppStorage(SettingsKeys.appearance) private var appearanceRawValue = AppAppearance.defaultValue.rawValue
    @StateObject private var libraryService = MusicLibraryService()
    @StateObject private var playbackService = MusicPlaybackService()
    @StateObject private var pinnedPlaylistStore = PinnedPlaylistStore()
    @StateObject private var generatedQueueSession = GeneratedQueueSession()
    @StateObject private var playlistCoverStore = PlaylistCoverStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(libraryService)
                .environmentObject(playbackService)
                .environmentObject(pinnedPlaylistStore)
                .environmentObject(generatedQueueSession)
                .environmentObject(playlistCoverStore)
                .tint(Color("AccentColor"))
                .background {
                    WindowAppearance(style: interfaceStyle)
                }
        }
    }

    private var interfaceStyle: UIUserInterfaceStyle {
        switch AppAppearance.resolved(rawValue: appearanceRawValue) {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Applies the Appearance setting to the whole window rather than through
/// `preferredColorScheme`, which leaves an open sheet such as Settings in the
/// old appearance. Changes crossfade so every layer switches together.
private struct WindowAppearance: UIViewRepresentable {
    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> WindowAppearanceView {
        let view = WindowAppearanceView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: WindowAppearanceView, context: Context) {
        view.style = style
    }
}

private final class WindowAppearanceView: UIView {
    var style: UIUserInterfaceStyle = .unspecified {
        didSet {
            apply(animated: true)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        apply(animated: false)
    }

    private func apply(animated: Bool) {
        guard let window, window.overrideUserInterfaceStyle != style else {
            return
        }
        guard animated else {
            window.overrideUserInterfaceStyle = style
            return
        }
        UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
            window.overrideUserInterfaceStyle = self.style
        }
    }
}
