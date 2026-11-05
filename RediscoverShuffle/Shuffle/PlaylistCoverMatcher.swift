import Foundation

/// Pairs the app's playlists, which come from `MediaPlayer`, with the ones
/// MusicKit returns, which carry Music's own cover. Apple documents no link
/// between the two kinds of ID, so this tries the forms MusicKit is known to
/// use for library items, then falls back to names that are unique on both
/// sides. A Music playlist is never paired twice.
enum PlaylistCoverMatcher {
    struct LibraryEntry: Equatable, Sendable {
        let persistentID: UInt64
        let name: String
    }

    struct MusicEntry: Equatable, Sendable {
        let id: String
        let name: String
    }

    /// The ways MusicKit may spell a `MediaPlayer` persistent ID: as the
    /// unsigned number, or as the signed number with the same bits.
    static func idCandidates(for persistentID: UInt64) -> [String] {
        let unsigned = String(persistentID)
        let signed = String(Int64(bitPattern: persistentID))
        return unsigned == signed ? [unsigned] : [unsigned, signed]
    }

    /// Returns the Music playlist ID for each library playlist that could be
    /// paired, keyed by persistent ID.
    static func match(library: [LibraryEntry], music: [MusicEntry]) -> [UInt64: String] {
        var musicIDs = Set(music.map(\.id))
        var matches: [UInt64: String] = [:]

        for entry in library {
            if let id = idCandidates(for: entry.persistentID).first(where: musicIDs.contains) {
                matches[entry.persistentID] = id
                musicIDs.remove(id)
            }
        }

        let unmatchedLibrary = library.filter { matches[$0.persistentID] == nil }
        let unmatchedMusic = music.filter { musicIDs.contains($0.id) }
        let libraryNameCounts = Dictionary(grouping: unmatchedLibrary, by: { normalized($0.name) }).mapValues(\.count)
        let musicByName = Dictionary(grouping: unmatchedMusic, by: { normalized($0.name) })

        for entry in unmatchedLibrary {
            let name = normalized(entry.name)
            guard !name.isEmpty,
                  libraryNameCounts[name] == 1,
                  let candidates = musicByName[name],
                  candidates.count == 1 else {
                continue
            }
            matches[entry.persistentID] = candidates[0].id
        }
        return matches
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
