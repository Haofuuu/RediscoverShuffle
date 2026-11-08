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
    /// Read once when the library loads, so rows, sorting and shuffling never
    /// go back to MediaPlayer. A play reloads the library, which brings the
    /// new count.
    let playCount: Int

    init(id: PlaylistEntryIdentifier, mediaItem: MPMediaItem, originalIndex: Int) {
        self.id = id
        self.mediaItem = mediaItem
        self.originalIndex = originalIndex
        playCount = max(0, mediaItem.playCount)
    }

    var title: String {
        nonempty(mediaItem.title) ?? String(localized: "Unknown Title")
    }

    var artist: String {
        nonempty(mediaItem.artist) ?? String(localized: "Unknown Artist")
    }

    var albumTitle: String {
        nonempty(mediaItem.albumTitle) ?? String(localized: "Unknown Album")
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
    /// How much of the playlist is waiting to be rediscovered. Read once when
    /// the library loads, so lists never re-read play counts while scrolling.
    let rediscoveryInsight: RediscoveryInsight
    let signature: Signature

    /// Everything about a playlist that the screens show, so a reload that
    /// changes none of it can be recognised and skipped.
    struct Signature: Equatable {
        let id: MPMediaEntityPersistentID
        let name: String
        let songIDs: [MPMediaEntityPersistentID]
        let playCounts: [Int]
        let coverCount: Int
    }

    init(
        id: MPMediaEntityPersistentID,
        name: String,
        entries: [PlaylistEntry],
        coverArtworks: [MPMediaItemArtwork]
    ) {
        self.id = id
        self.name = name
        self.entries = entries
        self.coverArtworks = coverArtworks
        let playCounts = entries.map(\.playCount)
        rediscoveryInsight = RediscoveryInsight(playCounts: playCounts)
        signature = Signature(
            id: id,
            name: name,
            songIDs: entries.map(\.mediaItem.persistentID),
            playCounts: playCounts,
            coverCount: coverArtworks.count
        )
    }

    var artwork: MPMediaItemArtwork? {
        coverArtworks.first
    }

    var persistentIDString: String {
        String(id)
    }
}

struct NowPlayingSnapshot {
    let id: MPMediaEntityPersistentID
    let title: String
    let artist: String
    let artwork: MPMediaItemArtwork?
    /// Zero when Music doesn't know the song's length.
    let duration: TimeInterval
}
