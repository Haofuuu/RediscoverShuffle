import Foundation
import MediaPlayer
import MusicKit

/// The covers Music itself shows for playlists: a custom image, or Music's
/// collage of the playlist's first albums. `MediaPlayer` doesn't expose them,
/// so they come from MusicKit, read under the Media & Apple Music permission
/// the app already has; this never asks for it. Playlists Music has no cover
/// for, or that can't be paired, keep the mosaic built from their songs.
@MainActor
final class PlaylistCoverStore: ObservableObject {
    struct Cover: Equatable {
        let artwork: Artwork
        /// Colours read from the cover for its playlist's colour field. Empty
        /// until they load, or when the cover can't be read.
        let swatches: [PaletteColor]
    }

    @Published private(set) var covers: [MPMediaEntityPersistentID: Cover] = [:]

    private var loadTask: Task<Void, Never>?
    /// Playlists already looked up one by one this session, with what was
    /// found, so later refreshes don't repeat the queries.
    private var lookups: [MPMediaEntityPersistentID: Playlist?] = [:]
    private var swatchCache: [Artwork: [PaletteColor]] = [:]
    /// What the covers were last loaded for. Every play changes the library's
    /// play counts, but covers only depend on each playlist's name and songs,
    /// so a play doesn't send MusicKit for every cover again.
    private var loadedFor: [CoverKey] = []

    private struct CoverKey: Equatable {
        let id: MPMediaEntityPersistentID
        let name: String
        let songIDs: [MPMediaEntityPersistentID]
    }

    func reload(for playlists: [LibraryPlaylist]) {
        guard !playlists.isEmpty, MusicAuthorization.currentStatus == .authorized else {
            loadTask?.cancel()
            loadedFor = []
            covers = [:]
            return
        }
        let key = playlists.map {
            CoverKey(id: $0.id, name: $0.name, songIDs: $0.signature.songIDs)
        }
        guard key != loadedFor else {
            return
        }
        loadTask?.cancel()
        let library = playlists.map {
            PlaylistCoverMatcher.LibraryEntry(persistentID: $0.id, name: $0.name)
        }
        loadTask = Task { [weak self] in
            await self?.load(library, for: key)
        }
    }

    private func load(_ library: [PlaylistCoverMatcher.LibraryEntry], for key: [CoverKey]) async {
        // Without the MusicKit App Service, or on a device without a library,
        // the request fails and every playlist keeps its mosaic; the next
        // reload tries again.
        guard let musicPlaylists = try? await Self.libraryPlaylists(), !Task.isCancelled else {
            return
        }

        let byID = Dictionary(musicPlaylists.map { ($0.id.rawValue, $0) }, uniquingKeysWith: { first, _ in first })
        let matches = PlaylistCoverMatcher.match(
            library: library,
            music: musicPlaylists.map { PlaylistCoverMatcher.MusicEntry(id: $0.id.rawValue, name: $0.name) }
        )
        var found: [MPMediaEntityPersistentID: Playlist] = [:]
        for (persistentID, musicID) in matches {
            found[persistentID] = byID[musicID]
        }

        // MusicKit's library filters accept MediaPlayer persistent IDs even
        // where the IDs it returns are spelled differently.
        for entry in library where found[entry.persistentID] == nil {
            if lookups[entry.persistentID] == nil {
                lookups[entry.persistentID] = .some(await Self.lookUpPlaylist(persistentID: entry.persistentID))
                guard !Task.isCancelled else {
                    return
                }
            }
            if let playlist = lookups[entry.persistentID] ?? nil {
                found[entry.persistentID] = playlist
            }
        }

        let artworks = found.compactMapValues(\.artwork)
        publish(artworks)
        loadedFor = key

        for artwork in Set(artworks.values) where swatchCache[artwork] == nil {
            swatchCache[artwork] = await ArtworkPalette.swatches(of: artwork)
            guard !Task.isCancelled else {
                return
            }
        }
        publish(artworks)
    }

    private func publish(_ artworks: [MPMediaEntityPersistentID: Artwork]) {
        let updated = artworks.mapValues { Cover(artwork: $0, swatches: swatchCache[$0] ?? []) }
        if updated != covers {
            covers = updated
        }
    }

    private static func libraryPlaylists() async throws -> [Playlist] {
        var batch = try await MusicLibraryRequest<Playlist>().response().items
        var playlists = Array(batch)
        while batch.hasNextBatch, let next = try await batch.nextBatch() {
            playlists += next
            batch = next
        }
        return playlists
    }

    private static func lookUpPlaylist(persistentID: MPMediaEntityPersistentID) async -> Playlist? {
        for id in PlaylistCoverMatcher.idCandidates(for: persistentID) {
            var request = MusicLibraryRequest<Playlist>()
            request.filter(matching: \.id, equalTo: MusicItemID(id))
            if let playlist = try? await request.response().items.first {
                return playlist
            }
        }
        return nil
    }
}
