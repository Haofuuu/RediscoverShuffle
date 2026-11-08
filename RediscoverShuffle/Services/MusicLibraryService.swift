import Combine
import Foundation
import MediaPlayer
import os

@MainActor
final class MusicLibraryService: ObservableObject {
    @Published private(set) var authorizationStatus: MPMediaLibraryAuthorizationStatus
    @Published private(set) var playlists: [LibraryPlaylist] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private lazy var mediaLibrary = MPMediaLibrary.default()
    private var libraryChangeObserver: NSObjectProtocol?
    private var pendingRefresh: Task<Void, Never>?
    /// Albums whose artwork is known to draw. Test-drawing artwork is the
    /// costliest part of a reload, and artwork that has drawn keeps drawing.
    private static var drawableAlbumIDs = Set<MPMediaEntityPersistentID>()
    /// Marks library reloads and queue generation for Instruments, so their
    /// cost can be read on a device.
    static let signposter = OSSignposter(subsystem: "RediscoverShuffle", category: "Performance")

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
                self?.scheduleRefresh()
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
            // The first load shows the library at once. Later ones, from
            // returning to the app or a library change, are merged: iOS often
            // sends both together.
            if playlists.isEmpty {
                refreshPlaylists()
            } else {
                scheduleRefresh()
            }
        } else {
            pendingRefresh?.cancel()
            playlists = []
        }
    }

    /// Reloads once things settle, however many requests arrive meanwhile.
    func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else {
                return
            }
            self?.refreshPlaylists()
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
        pendingRefresh?.cancel()
        guard MPMediaLibrary.authorizationStatus() == .authorized else {
            authorizationStatus = MPMediaLibrary.authorizationStatus()
            playlists = []
            isLoading = false
            return
        }
        let interval = Self.signposter.beginInterval("Load library")
        defer {
            Self.signposter.endInterval("Load library", interval)
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
        let loaded = collections.map(Self.makePlaylist).sorted { left, right in
            let comparison = left.name.localizedStandardCompare(right.name)
            if comparison == .orderedSame {
                return left.id < right.id
            }
            return comparison == .orderedAscending
        }

        // A reload that finds nothing new leaves the screens, and MusicKit's
        // covers, alone.
        if loaded.map(\.signature) != playlists.map(\.signature) {
            playlists = loaded
        }
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
            // Songs whose artwork hasn't downloaded from iCloud still return an
            // artwork object, but it draws nothing and would leave a blank
            // tile. Another song from the same album may still have it.
            let albumID = item.albumPersistentID
            guard let artwork = item.artwork, !seenAlbumIDs.contains(albumID) else {
                continue
            }
            // Songs without an album all share ID 0, so they're always checked.
            let isKnownDrawable = albumID != 0 && drawableAlbumIDs.contains(albumID)
            guard isKnownDrawable || artwork.image(at: CGSize(width: 32, height: 32)) != nil else {
                continue
            }
            if albumID != 0 {
                drawableAlbumIDs.insert(albumID)
            }
            seenAlbumIDs.insert(albumID)
            artworks.append(artwork)
            if artworks.count == 4 {
                break
            }
        }
        return artworks
    }
}
