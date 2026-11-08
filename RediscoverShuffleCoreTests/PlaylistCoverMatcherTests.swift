import Testing
@testable import RediscoverShuffleCore

@Suite("Playlist cover matching")
struct PlaylistCoverMatcherTests {
    private typealias Library = PlaylistCoverMatcher.LibraryEntry
    private typealias Music = PlaylistCoverMatcher.MusicEntry

    /// Above `Int64.max`, so its signed spelling differs.
    private static let largeID: UInt64 = 9_601_744_824_086_363_441

    @Test("Large persistent IDs have a signed spelling too")
    func idCandidates() {
        #expect(PlaylistCoverMatcher.idCandidates(for: 42) == ["42"])
        #expect(PlaylistCoverMatcher.idCandidates(for: Self.largeID) == ["9601744824086363441", "-8844999249623188175"])
    }

    @Test("IDs match in either spelling")
    func idMatch() {
        let matches = PlaylistCoverMatcher.match(
            library: [Library(persistentID: 42, name: "Focus"), Library(persistentID: Self.largeID, name: "Drive")],
            music: [Music(id: "-8844999249623188175", name: "Drive"), Music(id: "42", name: "Focus")]
        )
        #expect(matches == [42: "42", Self.largeID: "-8844999249623188175"])
    }

    @Test("Unique names match when IDs don't")
    func nameMatch() {
        let matches = PlaylistCoverMatcher.match(
            library: [Library(persistentID: 1, name: "Focus"), Library(persistentID: 2, name: "Drive")],
            music: [Music(id: "p.abc", name: " Focus "), Music(id: "p.def", name: "Sleep")]
        )
        #expect(matches == [1: "p.abc"])
    }

    @Test("Repeated names are left unmatched", arguments: [
        ([Library(persistentID: 1, name: "Mix"), Library(persistentID: 2, name: "Mix")], [Music(id: "p.a", name: "Mix")]),
        ([Library(persistentID: 1, name: "Mix")], [Music(id: "p.a", name: "Mix"), Music(id: "p.b", name: "Mix")]),
    ])
    func repeatedNames(library: [PlaylistCoverMatcher.LibraryEntry], music: [PlaylistCoverMatcher.MusicEntry]) {
        #expect(PlaylistCoverMatcher.match(library: library, music: music).isEmpty)
    }

    @Test("A playlist matched by ID isn't offered again by name")
    func idTakesPriority() {
        let matches = PlaylistCoverMatcher.match(
            library: [Library(persistentID: 7, name: "Old Name"), Library(persistentID: 8, name: "Mix")],
            music: [Music(id: "7", name: "Mix")]
        )
        #expect(matches == [7: "7"])
    }
}
