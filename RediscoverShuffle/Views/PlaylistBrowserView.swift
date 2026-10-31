import SwiftUI

struct PlaylistBrowserView: View {
    @Environment(\.editMode) private var editMode
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var pinnedPlaylistStore: PinnedPlaylistStore
    @EnvironmentObject private var generatedQueueSession: GeneratedQueueSession
    @AppStorage(SettingsKeys.lastSelectedPlaylistID) private var lastSelectedPlaylistID = ""
    @State private var searchText = ""
    @State private var showsSettings = false
    @State private var showsSavedQueue = false
    @Namespace private var playlistTransition

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
                    title: String(localized: "No Playlists Found"),
                    message: String(localized: "Add a playlist to your library in the Music app, then refresh here."),
                    actionTitle: String(localized: "Refresh"),
                    action: libraryService.refreshPlaylists
                )
            } else if matchingPlaylists.isEmpty {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: String(localized: "No Matches"),
                    message: String(
                        format: String(localized: "No playlist name contains “%@”."),
                        locale: .current,
                        searchText
                    ),
                    actionTitle: nil,
                    action: nil
                )
            } else {
                List {
                    if trimmedSearch.isEmpty,
                       let lastQueueViewModel = generatedQueueSession.lastQueueViewModel {
                        ContinueQueueCard(viewModel: lastQueueViewModel, transition: playlistTransition) {
                            showsSavedQueue = true
                        }
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    if !pinnedPlaylists.isEmpty {
                        Section {
                            ForEach(pinnedPlaylists) { playlist in
                                playlistLink(for: playlist)
                            }
                            .onMove(perform: movePinnedPlaylists)
                            .moveDisabled(!canReorderPinnedPlaylists)
                        } header: {
                            sectionTitle(String(localized: "Pinned"))
                        }
                    }

                    if !unpinnedPlaylists.isEmpty {
                        Section {
                            ForEach(unpinnedPlaylists) { playlist in
                                playlistLink(for: playlist)
                            }
                        } header: {
                            if !pinnedPlaylists.isEmpty {
                                sectionTitle(String(localized: "All Playlists"))
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable {
                    libraryService.refreshPlaylists()
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("Playlists")
        .navigationBarTitleDisplayMode(.large)
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
                    showsSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityHint("Opens Rediscover Shuffle settings")
            }
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .navigationDestination(isPresented: $showsSavedQueue) {
            if let savedQueue = generatedQueueSession.lastQueueViewModel {
                PlaylistDetailView(playlist: savedQueue.playlist, savedQueue: savedQueue)
                    .zoomTransition(from: ContinueQueueCard.transitionID, in: playlistTransition)
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
            Text(libraryService.errorMessage ?? String(localized: "An unknown error occurred."))
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

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(Color.primary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    private func playlistLink(for playlist: LibraryPlaylist) -> some View {
        NavigationLink {
            PlaylistDetailView(
                playlist: playlist,
                savedQueue: generatedQueueSession.lastQueueViewModel.flatMap {
                    $0.playlist.id == playlist.id ? $0 : nil
                }
            )
            .zoomTransition(from: playlist.id, in: playlistTransition)
        } label: {
            PlaylistRow(
                playlist: playlist,
                isLastSelected: playlist.persistentIDString == lastSelectedPlaylistID,
                isPinned: pinnedPlaylistStore.isPinned(playlist.persistentIDString),
                transition: playlistTransition
            )
        }
        .listRowBackground(Color.clear)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            pinButton(for: playlist)
        }
        .contextMenu {
            pinButton(for: playlist)
            if canReorderPinnedPlaylists,
               let index = availablePinnedPlaylists.firstIndex(where: { $0.id == playlist.id }) {
                Button("Move Up", systemImage: "arrow.up") {
                    movePinnedPlaylists(from: IndexSet(integer: index), to: index - 1)
                }
                .disabled(index == 0)
                Button("Move Down", systemImage: "arrow.down") {
                    movePinnedPlaylists(from: IndexSet(integer: index), to: index + 2)
                }
                .disabled(index == availablePinnedPlaylists.count - 1)
            }
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
                isPinned
                    ? String(localized: "Unpin Playlist")
                    : String(localized: "Pin Playlist"),
                systemImage: isPinned ? "pin.slash" : "pin.fill"
            )
        }
        .tint(Color("AccentColor"))
    }
}

private struct PlaylistRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let playlist: LibraryPlaylist
    let isLastSelected: Bool
    let isPinned: Bool
    let transition: Namespace.ID

    private var isEmpty: Bool {
        playlist.entries.isEmpty
    }

    private var detailText: String {
        let count = isEmpty ? String(localized: "Empty") : localizedSongCount(playlist.entries.count)
        guard isLastSelected else {
            return count
        }
        return String(
            format: String(localized: "%@ · %@"),
            locale: .current,
            count,
            String(localized: "Last opened")
        )
    }

    private var playlistAccessibilityLabel: String {
        var parts = [playlist.name, isEmpty ? String(localized: "Empty") : localizedSongCount(playlist.entries.count)]
        if isPinned {
            parts.append(String(localized: "pinned"))
        }
        if isLastSelected {
            parts.append(String(localized: "last opened"))
        }
        return parts.joined(separator: String(localized: ", "))
    }

    private var playlistAccessibilityHint: String {
        if isPinned {
            return String(localized: "Touch and hold to unpin or move this playlist. Use Edit to drag pinned playlists.")
        }
        return String(localized: "Swipe right or touch and hold to pin this playlist")
    }

    var body: some View {
        HStack(spacing: 14) {
            PlaylistArtworkView(playlist: playlist, size: 56)
                .opacity(isEmpty ? 0.55 : 1)
                .zoomSource(id: playlist.id, in: transition)

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isEmpty ? Color("SecondaryText") : Color.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(Color("SecondaryText"))
            }

            Spacer(minLength: 8)

            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.footnote)
                    .foregroundStyle(Color("AccentColor"))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(playlistAccessibilityLabel)
        .accessibilityHint(playlistAccessibilityHint)
    }
}

/// Entry point back into the most recent queue, drawn in that playlist's
/// own colours so it reads as a way back into it.
private struct ContinueQueueCard: View {
    static let transitionID = "continueQueue"

    @EnvironmentObject private var playbackService: MusicPlaybackService
    @ObservedObject var viewModel: PlaylistViewModel
    let transition: Namespace.ID
    let open: () -> Void

    private var isLive: Bool {
        playbackService.generatedQueueProgress?.queueID == viewModel.queueID
    }

    /// The card is always dark so the field shows the playlist's colours at
    /// full depth, in light mode too.
    private var palette: ArtworkColorPalette {
        ArtworkPalette.palette(for: viewModel.playlist, appearance: .dark)
    }

    private var fieldArrangement: Int {
        let id = viewModel.queueID.uuid
        return Int(id.0) << 8 | Int(id.1)
    }

    private var progressFraction: Double? {
        guard let position = viewModel.playbackPosition, !viewModel.generatedOrder.isEmpty else {
            return nil
        }
        return Double(position + 1) / Double(viewModel.generatedOrder.count)
    }

    private var detailText: String {
        let count = viewModel.generatedOrder.count
        guard let position = viewModel.playbackPosition, count > 0 else {
            return localizedSongCount(count)
        }
        return String(
            format: isLive
                ? String(localized: "Song %lld of %lld")
                : String(localized: "Continue from song %lld of %lld"),
            locale: .current,
            Int64(min(position + 1, count)),
            Int64(count)
        )
    }

    private var accessibilityText: String {
        var parts = [viewModel.playlist.name]
        if isLive {
            parts.append(String(localized: "Now playing"))
        }
        parts.append(detailText)
        return parts.joined(separator: String(localized: ", "))
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                PlaylistArtworkView(playlist: viewModel.playlist, size: 72)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                    .zoomSource(id: Self.transitionID, in: transition)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.playlist.name)
                        .font(.headline)
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if isLive {
                            NowPlayingIndicator(isPlaying: playbackService.isPlaying)
                        }
                        Text(detailText)
                            .foregroundStyle(Color(palette.secondaryText))
                    }
                    .font(.subheadline)
                    if let progressFraction {
                        ProgressView(value: progressFraction)
                            .tint(Color(palette.accent))
                            .padding(.top, 4)
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(palette.secondaryText))
                    .accessibilityHidden(true)
            }
            .padding(16)
            .background {
                ColorField(
                    palette: palette,
                    arrangement: fieldArrangement,
                    isPlaying: isLive && playbackService.isPlaying
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color(palette.ground).opacity(0.3), radius: 16, y: 8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .environment(\.colorScheme, .dark)
            .screenTheme(palette)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens your most recent queue without changing its order")
    }
}
