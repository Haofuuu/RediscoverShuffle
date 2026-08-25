import Combine
import Foundation

@MainActor
final class PinnedPlaylistStore: ObservableObject {
    @Published private(set) var pinnedPlaylistIDs: [String]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        var seenIDs = Set<String>()
        pinnedPlaylistIDs = (defaults.stringArray(forKey: SettingsKeys.pinnedPlaylistIDs) ?? [])
            .filter { seenIDs.insert($0).inserted }
    }

    func isPinned(_ playlistID: String) -> Bool {
        pinnedPlaylistIDs.contains(playlistID)
    }

    func toggle(_ playlistID: String) {
        if let index = pinnedPlaylistIDs.firstIndex(of: playlistID) {
            pinnedPlaylistIDs.remove(at: index)
        } else {
            pinnedPlaylistIDs.append(playlistID)
        }

        persist()
    }

    func updateOrder(_ orderedVisibleIDs: [String]) {
        let visibleIDSet = Set(orderedVisibleIDs)
        guard visibleIDSet.count == orderedVisibleIDs.count,
              visibleIDSet.isSubset(of: Set(pinnedPlaylistIDs)) else {
            return
        }

        let unavailableIDs = pinnedPlaylistIDs.filter { !visibleIDSet.contains($0) }
        pinnedPlaylistIDs = orderedVisibleIDs + unavailableIDs
        persist()
    }

    private func persist() {
        defaults.set(pinnedPlaylistIDs, forKey: SettingsKeys.pinnedPlaylistIDs)
    }
}
