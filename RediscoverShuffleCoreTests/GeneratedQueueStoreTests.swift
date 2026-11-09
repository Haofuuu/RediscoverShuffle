import Foundation
import Testing
@testable import RediscoverShuffleCore

@Suite("Generated queue store")
struct GeneratedQueueStoreTests {
    @Test("Clearing the queue leaves unrelated preferences unchanged")
    func clearDoesNotAffectPreferences() throws {
        let identifier = UUID().uuidString
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RediscoverShuffleTests-\(identifier)", isDirectory: true)
        let queueFile = temporaryDirectory.appendingPathComponent("queue.json")
        let defaultsSuite = "RediscoverShuffleTests.\(identifier)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!

        defer {
            defaults.removePersistentDomain(forName: defaultsSuite)
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        defaults.set(AppAppearance.dark.rawValue, forKey: SettingsKeys.appearance)
        defaults.set(false, forKey: SettingsKeys.showPlayCounts)
        defaults.set(4.0, forKey: SettingsKeys.rediscoveryStrength)

        let store = GeneratedQueueStore(fileURL: queueFile)
        let queue = StoredGeneratedQueue(
            schemaVersion: StoredGeneratedQueue.currentSchemaVersion,
            queueID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            playlistPersistentID: "42",
            entries: [
                StoredGeneratedQueue.Entry(originalIndex: 3, mediaItemPersistentID: "99")
            ],
            playbackPosition: 0,
            submittedQueueID: UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
            playbackPlayerIndex: 0
        )

        #expect(store.save(queue))
        #expect(store.hasSavedQueue)
        #expect(store.load() == queue)

        try store.clear()

        #expect(!store.hasSavedQueue)
        #expect(store.load() == nil)
        #expect(defaults.string(forKey: SettingsKeys.appearance) == AppAppearance.dark.rawValue)
        #expect(defaults.object(forKey: SettingsKeys.showPlayCounts) as? Bool == false)
        #expect(defaults.double(forKey: SettingsKeys.rediscoveryStrength) == 4.0)
    }

    @Test("The order Music was handed survives a reshuffle saved after it")
    func playingOrderRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RediscoverShuffleTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let store = GeneratedQueueStore(fileURL: directory.appendingPathComponent("queue.json"))
        let queue = StoredGeneratedQueue(
            schemaVersion: StoredGeneratedQueue.currentSchemaVersion,
            queueID: UUID(),
            playlistPersistentID: "42",
            entries: [
                StoredGeneratedQueue.Entry(originalIndex: 1, mediaItemPersistentID: "7"),
                StoredGeneratedQueue.Entry(originalIndex: 0, mediaItemPersistentID: "7")
            ],
            playbackPosition: nil,
            submittedQueueID: UUID(),
            playbackPlayerIndex: 3,
            playingEntries: [
                StoredGeneratedQueue.Entry(originalIndex: 0, mediaItemPersistentID: "7"),
                StoredGeneratedQueue.Entry(originalIndex: 1, mediaItemPersistentID: "7")
            ]
        )

        #expect(store.save(queue))
        #expect(store.load() == queue)
    }

    @Test("Queues saved before the playing order was kept still load")
    func earlierFilesLoad() throws {
        let json = """
        {"schemaVersion":1,"queueID":"11111111-1111-1111-1111-111111111111",
         "playlistPersistentID":"42","entries":[{"originalIndex":3,"mediaItemPersistentID":"99"}],
         "playbackPosition":0,"submittedQueueID":"11111111-1111-1111-1111-111111111111",
         "playbackPlayerIndex":0}
        """
        let queue = try JSONDecoder().decode(StoredGeneratedQueue.self, from: Data(json.utf8))

        #expect(queue.entries.count == 1)
        #expect(queue.playingEntries == nil)
    }
}
