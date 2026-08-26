import Testing
@testable import RediscoverShuffleCore

@Suite("Playlist song sorting")
struct PlaylistSongSortTests {
    @Test("Default preserves the playlist source order")
    func defaultOrder() {
        #expect(sortedIDs(fixtures, by: .defaultOrder) == ["alpha", "beta", "gamma", "delta"])
    }

    @Test("Play count sorts in both directions with source-order ties")
    func playCountDirections() {
        #expect(sortedIDs(fixtures, by: .playsLowToHigh) == ["beta", "gamma", "alpha", "delta"])
        #expect(sortedIDs(fixtures, by: .playsHighToLow) == ["delta", "alpha", "beta", "gamma"])
    }

    @Test("Singer sorting uses artist, title, then source order")
    func singers() {
        let songs = [
            TestSong(id: "third", originalIndex: 2, playCount: 0, artist: "Zara", title: "One"),
            TestSong(id: "second", originalIndex: 1, playCount: 0, artist: "Amy", title: "Two"),
            TestSong(id: "first", originalIndex: 0, playCount: 0, artist: "Amy", title: "Two"),
            TestSong(id: "before", originalIndex: 3, playCount: 0, artist: "Amy", title: "Before"),
        ]

        #expect(sortedIDs(songs, by: .singers) == ["before", "first", "second", "third"])
    }

    private var fixtures: [TestSong] {
        [
            TestSong(id: "delta", originalIndex: 3, playCount: 20, artist: "D", title: "D"),
            TestSong(id: "gamma", originalIndex: 2, playCount: 1, artist: "C", title: "C"),
            TestSong(id: "alpha", originalIndex: 0, playCount: 8, artist: "A", title: "A"),
            TestSong(id: "beta", originalIndex: 1, playCount: 1, artist: "B", title: "B"),
        ]
    }

    private func sortedIDs(
        _ songs: [TestSong],
        by option: PlaylistSongSortOption
    ) -> [String] {
        option.sorted(songs) {
            PlaylistSongSortValue(
                originalIndex: $0.originalIndex,
                playCount: $0.playCount,
                artist: $0.artist,
                title: $0.title
            )
        }
        .map(\.id)
    }
}

private struct TestSong {
    let id: String
    let originalIndex: Int
    let playCount: Int
    let artist: String
    let title: String
}
