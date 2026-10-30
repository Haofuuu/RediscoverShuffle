import Combine
import Foundation
import MediaPlayer

@MainActor
final class MusicLibraryService: ObservableObject {
    @Published private(set) var authorizationStatus: MPMediaLibraryAuthorizationStatus
    @Published private(set) var playlists: [LibraryPlaylist] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private lazy var mediaLibrary = MPMediaLibrary.default()
    private var libraryChangeObserver: NSObjectProtocol?

    init() {
        authorizationStatus = MPMediaLibrary.authorizationStatus()
    }

    private func startObservingLibrary() {
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
            Task { @MainActor in
                MPMediaLibrary.default().endGeneratingLibraryChangeNotifications()
            }
        }
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
        if libraryChangeObserver == nil {
            startObservingLibrary()
        }
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
        let name = trimmedName.flatMap { $0.isEmpty ? nil : $0 }
            ?? String(localized: "Untitled Playlist")
        return LibraryPlaylist(
            id: playlistID,
            name: name,
            entries: entries,
            coverArtworks: coverArtworks(from: items)
        )
    }

    /// Picks artwork from up to four different albums, scanning only the start
    /// of long playlists so large libraries stay fast to load.
    private static func coverArtworks(from items: [MPMediaItem]) -> [MPMediaItemArtwork] {
        var seenAlbumIDs = Set<MPMediaEntityPersistentID>()
        var artworks: [MPMediaItemArtwork] = []
        for item in items.prefix(60) {
            guard let artwork = item.artwork,
                  seenAlbumIDs.insert(item.albumPersistentID).inserted else {
                continue
            }
            artworks.append(artwork)
            if artworks.count == 4 {
                break
            }
        }
        return artworks
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
