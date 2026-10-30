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
}
