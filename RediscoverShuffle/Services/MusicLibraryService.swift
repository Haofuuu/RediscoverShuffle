import Combine
import Foundation
import MediaPlayer

@MainActor
final class MusicLibraryService: ObservableObject {
    @Published private(set) var authorizationStatus: MPMediaLibraryAuthorizationStatus
    @Published private(set) var playlists: [LibraryPlaylist] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let mediaLibrary = MPMediaLibrary.default()
    private var libraryChangeObserver: NSObjectProtocol?

    init() {
        authorizationStatus = MPMediaLibrary.authorizationStatus()
        mediaLibrary.beginGeneratingLibraryChangeNotifications()
        libraryChangeObserver = NotificationCenter.default.addObserver(
            forName: .MPMediaLibraryDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPlaylists()
            }
        }
    }

    deinit {
        if let libraryChangeObserver {
            NotificationCenter.default.removeObserver(libraryChangeObserver)
        }
        mediaLibrary.endGeneratingLibraryChangeNotifications()
    }

    func synchronizeAuthorizationAndLoad() {
        authorizationStatus = MPMediaLibrary.authorizationStatus()
        if authorizationStatus == .authorized {
            refreshPlaylists()
        } else {
            playlists = []
        }
    }

    func requestAuthorization() {
        guard authorizationStatus == .notDetermined else {
            synchronizeAuthorizationAndLoad()
            return
        }

        isLoading = true
        MPMediaLibrary.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                self.authorizationStatus = status
                self.isLoading = false
                if status == .authorized {
                    self.refreshPlaylists()
                } else {
                    self.playlists = []
                }
            }
        }
    }

    func refreshPlaylists() {
        guard MPMediaLibrary.authorizationStatus() == .authorized else {
            authorizationStatus = MPMediaLibrary.authorizationStatus()
            playlists = []
            isLoading = false
            return
        }

        authorizationStatus = .authorized
        isLoading = true
        errorMessage = nil

        let collections = (MPMediaQuery.playlists().collections ?? []).compactMap {
            $0 as? MPMediaPlaylist
        }
        playlists = collections.map(Self.makePlaylist).sorted { left, right in
            let comparison = left.name.localizedStandardCompare(right.name)
            if comparison == .orderedSame {
                return left.id < right.id
            }
            return comparison == .orderedAscending
        }

        reconcileStoredPlaylistSelection()
        isLoading = false
    }

    private static func makePlaylist(from playlist: MPMediaPlaylist) -> LibraryPlaylist {
        let playlistID = playlist.persistentID
        let items = playlist.items
        let entries = items.enumerated().map { index, item in
            PlaylistEntry(
                id: PlaylistEntryIdentifier(
                    playlistPersistentID: playlistID,
                    originalIndex: index
                ),
                mediaItem: item,
                originalIndex: index
            )
        }

        let trimmedName = playlist.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled Playlist"
        let artwork = items.first(where: { $0.artwork != nil })?.artwork

        return LibraryPlaylist(id: playlistID, name: name, entries: entries, artwork: artwork)
    }

    private func reconcileStoredPlaylistSelection() {
        let defaults = UserDefaults.standard
        guard let storedID = defaults.string(forKey: SettingsKeys.lastSelectedPlaylistID) else {
            return
        }
        if !playlists.contains(where: { $0.persistentIDString == storedID }) {
            defaults.removeObject(forKey: SettingsKeys.lastSelectedPlaylistID)
        }
    }
}
