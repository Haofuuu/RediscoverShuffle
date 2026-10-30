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
        nonempty(mediaItem.title) ?? String(localized: "Unknown Title")
    }

    var artist: String {
        nonempty(mediaItem.artist) ?? String(localized: "Unknown Artist")
    }

    var albumTitle: String {
        nonempty(mediaItem.albumTitle) ?? String(localized: "Unknown Album")
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
    /// Up to four artworks from distinct albums, used for the cover mosaic.
    let coverArtworks: [MPMediaItemArtwork]

    var artwork: MPMediaItemArtwork? {
        coverArtworks.first
    }

    var persistentIDString: String {
        String(id)
    }
}

struct NowPlayingSnapshot {
    let title: String
    let artist: String
    let artwork: MPMediaItemArtwork?
}
