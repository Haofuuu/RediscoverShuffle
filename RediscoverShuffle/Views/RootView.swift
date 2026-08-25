import MediaPlayer
import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var libraryService: MusicLibraryService

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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            libraryService.synchronizeAuthorizationAndLoad()
        }
    }
}
