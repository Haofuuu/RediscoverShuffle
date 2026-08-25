import SwiftUI

struct PlaylistBrowserView: View {
    @Environment(\.editMode) private var editMode
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var pinnedPlaylistStore: PinnedPlaylistStore
    @AppStorage(SettingsKeys.lastSelectedPlaylistID) private var lastSelectedPlaylistID = ""
    @State private var searchText = ""

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingPlaylists: [LibraryPlaylist] {
        if trimmedSearch.isEmpty {
            return libraryService.playlists
        }

        return libraryService.playlists.filter {
            $0.name.localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    private var availablePinnedPlaylists: [LibraryPlaylist] {
        let playlistsByID = Dictionary(
            uniqueKeysWithValues: libraryService.playlists.map { ($0.persistentIDString, $0) }
        )
        return pinnedPlaylistStore.pinnedPlaylistIDs.compactMap { playlistsByID[$0] }
    }

    private var pinnedPlaylists: [LibraryPlaylist] {
        let matchingIDs = Set(matchingPlaylists.map(\.persistentIDString))
        return availablePinnedPlaylists.filter { matchingIDs.contains($0.persistentIDString) }
    }

    private var unpinnedPlaylists: [LibraryPlaylist] {
        matchingPlaylists
            .filter { !pinnedPlaylistStore.isPinned($0.persistentIDString) }
            .sorted(by: alphabeticalPlaylistOrder)
    }

    private var canReorderPinnedPlaylists: Bool {
        trimmedSearch.isEmpty && availablePinnedPlaylists.count > 1
    }

    var body: some View {
        Group {
            if libraryService.isLoading && libraryService.playlists.isEmpty {
                ProgressView("Loading playlists…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if libraryService.playlists.isEmpty {
                EmptyStateView(
                    symbol: "music.note.list",
                    title: "No Playlists Found",
                    message: "Add a playlist to your library in the Music app, then refresh here.",
                    actionTitle: "Refresh",
                    action: libraryService.refreshPlaylists
                )
            } else if matchingPlaylists.isEmpty {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: "No Matches",
                    message: "No playlist name contains “\(searchText)”.",
                    actionTitle: nil,
                    action: nil
                )
            } else {
                List {
                    if !pinnedPlaylists.isEmpty {
                        Section("Pinned") {
                            ForEach(pinnedPlaylists) { playlist in
                                playlistLink(for: playlist)
                            }
                            .onMove(perform: movePinnedPlaylists)
                            .moveDisabled(!canReorderPinnedPlaylists)
                        }
                    }

                    if !unpinnedPlaylists.isEmpty {
                        Section {
                            ForEach(unpinnedPlaylists) { playlist in
                                playlistLink(for: playlist)
                            }
                        } header: {
                            if !pinnedPlaylists.isEmpty {
                                Text("Other Playlists")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    libraryService.refreshPlaylists()
                }
            }
        }
        .navigationTitle("Playlists")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search playlists")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if availablePinnedPlaylists.count > 1 {
                    EditButton()
                        .disabled(!trimmedSearch.isEmpty)
                        .accessibilityHint("Shows controls for reordering pinned playlists")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    libraryService.refreshPlaylists()
                } label: {
                    Label("Refresh Playlists", systemImage: "arrow.clockwise")
                }
                .disabled(libraryService.isLoading)
            }
        }
        .onChange(of: searchText) { _, newValue in
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                editMode?.wrappedValue = .inactive
            }
        }
        .onChange(of: pinnedPlaylistStore.pinnedPlaylistIDs) { _, _ in
            if availablePinnedPlaylists.count < 2 {
                editMode?.wrappedValue = .inactive
            }
        }
        .alert("Music Library Problem", isPresented: errorIsPresented) {
            Button("Dismiss", role: .cancel) {
                libraryService.errorMessage = nil
            }
        } message: {
            Text(libraryService.errorMessage ?? "An unknown error occurred.")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { libraryService.errorMessage != nil },
            set: { if !$0 { libraryService.errorMessage = nil } }
        )
    }

    private func alphabeticalPlaylistOrder(
        _ left: LibraryPlaylist,
        _ right: LibraryPlaylist
    ) -> Bool {
        let comparison = left.name.localizedStandardCompare(right.name)
        if comparison == .orderedSame {
            return left.id < right.id
        }
        return comparison == .orderedAscending
    }

    private func playlistLink(for playlist: LibraryPlaylist) -> some View {
        NavigationLink {
            PlaylistDetailView(playlist: playlist)
        } label: {
            PlaylistRow(
                playlist: playlist,
                isLastSelected: playlist.persistentIDString == lastSelectedPlaylistID,
                isPinned: pinnedPlaylistStore.isPinned(playlist.persistentIDString)
            )
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            pinButton(for: playlist)
        }
    }

    private func movePinnedPlaylists(from source: IndexSet, to destination: Int) {
        guard canReorderPinnedPlaylists else {
            return
        }

        var orderedIDs = availablePinnedPlaylists.map(\.persistentIDString)
        orderedIDs.move(fromOffsets: source, toOffset: destination)
        pinnedPlaylistStore.updateOrder(orderedIDs)
    }

    private func pinButton(for playlist: LibraryPlaylist) -> some View {
        let isPinned = pinnedPlaylistStore.isPinned(playlist.persistentIDString)
        return Button {
            pinnedPlaylistStore.toggle(playlist.persistentIDString)
        } label: {
            Label(
                isPinned ? "Unpin Playlist" : "Pin Playlist",
                systemImage: isPinned ? "pin.slash" : "pin.fill"
            )
        }
        .tint(isPinned ? .gray : .orange)
    }
}

private struct PlaylistRow: View {
    let playlist: LibraryPlaylist
    let isLastSelected: Bool
    let isPinned: Bool

    private var songCountText: String {
        "\(playlist.entries.count) \(playlist.entries.count == 1 ? "song" : "songs")"
    }

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(artwork: playlist.artwork, size: CGSize(width: 58, height: 58))

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(songCountText)
                        .foregroundStyle(.secondary)

                    if isLastSelected {
                        Text("•")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)

                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                            Text("Last opened")
                        }
                        .foregroundStyle(.tint)
                    }
                }
                .font(.subheadline)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(playlist.name), \(songCountText)\(isPinned ? ", pinned" : "")\(isLastSelected ? ", last opened" : "")")
        .accessibilityHint("Swipe right to \(isPinned ? "unpin" : "pin") this playlist\(isPinned ? ". Use Edit to reorder pinned playlists" : "")")
    }
}
