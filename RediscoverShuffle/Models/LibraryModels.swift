import Foundation
import MediaPlayer

struct PlaylistEntryIdentifier: Hashable {
    let playlistPersistentID: MPMediaEntityPersistentID
    let originalIndex: Int
}

struct PlaylistEntry: Identifiable {
    let id: PlaylistEntryIdentifier
    let mediaItem: MPMediaItem
    let originalIndex: Int

    var title: String {
        nonempty(mediaItem.title) ?? "Unknown Title"
    }

    var artist: String {
        nonempty(mediaItem.artist) ?? "Unknown Artist"
    }

    var albumTitle: String {
        nonempty(mediaItem.albumTitle) ?? "Unknown Album"
    }

    var playCount: Int {
        max(0, mediaItem.playCount)
    }

    var artwork: MPMediaItemArtwork? {
        mediaItem.artwork
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}

struct LibraryPlaylist: Identifiable {
    let id: MPMediaEntityPersistentID
    let name: String
    let entries: [PlaylistEntry]
    let artwork: MPMediaItemArtwork?

    var persistentIDString: String {
        String(id)
    }
}

struct NowPlayingSnapshot {
    let title: String
    let artist: String
    let artwork: MPMediaItemArtwork?

    static let empty = NowPlayingSnapshot(
        title: "Nothing Playing",
        artist: "Choose a playlist to begin",
        artwork: nil
    )
}

enum SettingsKeys {
    static let rediscoveryStrength = "rediscoveryStrength"
    static let lastSelectedPlaylistID = "lastSelectedPlaylistPersistentID"
    static let hasShownOnboarding = "hasShownOnboarding"
    static let pinnedPlaylistIDs = "pinnedPlaylistPersistentIDs"
}
