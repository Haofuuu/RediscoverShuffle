import Foundation

struct StoredGeneratedQueue: Codable, Equatable {
    static let currentSchemaVersion = 1

    struct Entry: Codable, Equatable {
        let originalIndex: Int
        let mediaItemPersistentID: String
    }

    let schemaVersion: Int
    let queueID: UUID
    let playlistPersistentID: String
    let entries: [Entry]
    let playbackPosition: Int?
    let submittedQueueID: UUID?
    let playbackPlayerIndex: Int?
    /// The order Music was handed, saved only once a reshuffle has dealt a
    /// new one since; otherwise `entries` is that order. Files saved before
    /// this existed leave it out.
    var playingEntries: [Entry]? = nil
}

struct GeneratedQueueStore {
    private let fileManager: FileManager
    let fileURL: URL

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil
    ) {
        self.fileManager = fileManager

        if let fileURL {
            self.fileURL = fileURL
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            self.fileURL = applicationSupport
                .appendingPathComponent("RediscoverShuffle", isDirectory: true)
                .appendingPathComponent("last-generated-queue.json")
        }
    }

    var hasSavedQueue: Bool {
        fileManager.fileExists(atPath: fileURL.path)
    }

    func load() -> StoredGeneratedQueue? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(StoredGeneratedQueue.self, from: data)
    }

    @discardableResult
    func save(_ queue: StoredGeneratedQueue) -> Bool {
        guard let data = try? JSONEncoder().encode(queue) else {
            return false
        }

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)

            var storedFileURL = fileURL
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? storedFileURL.setResourceValues(resourceValues)
            return true
        } catch {
            // Persistence is a convenience; an I/O failure must never prevent
            // queue generation or playback during the current session.
            return false
        }
    }

    func clear() throws {
        guard hasSavedQueue else {
            return
        }
        try fileManager.removeItem(at: fileURL)
    }
}
