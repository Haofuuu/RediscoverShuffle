import SwiftUI

struct PlaylistBrowserView: View {
    @Environment(\.editMode) private var editMode
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var pinnedPlaylistStore: PinnedPlaylistStore
    @EnvironmentObject private var generatedQueueSession: GeneratedQueueSession
    @AppStorage(SettingsKeys.lastSelectedPlaylistID) private var lastSelectedPlaylistID = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var showsSettings = false
    @State private var showsSavedQueue = false
    @State private var showsRemoveQueueError = false
    @State private var removeFeedbackTrigger = 0
    @State private var pinFeedbackTrigger = 0
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
        // The list stays on screen in every state, with loading and empty
        // states laid over it. Swapping it out leaves the large title
        // attached to nothing, so it collapses or jumps when the list comes
        // back.
        List {
            if !libraryService.playlists.isEmpty {
                PlaylistSearchField(text: $searchText, isFocused: $isSearchFocused)
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 10, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            if trimmedSearch.isEmpty,
               !libraryService.playlists.isEmpty,
               let lastQueueViewModel = generatedQueueSession.lastQueueViewModel {
                ContinueQueueCard(
                    viewModel: lastQueueViewModel,
                    transition: playlistTransition,
                    open: { showsSavedQueue = true },
                    remove: removeSavedQueue
                )
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

            // Shown as a row so the search field above it stays usable.
            if !libraryService.playlists.isEmpty, matchingPlaylists.isEmpty {
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
                .padding(.top, 48)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .refreshable {
            libraryService.refreshPlaylists()
        }
        .overlay {
            emptyState
        }
        .background(Color(.systemBackground))
        .navigationTitle("Playlists")
        .navigationBarTitleDisplayMode(.large)
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
        .alert("Could Not Remove Queue", isPresented: $showsRemoveQueueError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Rediscover Shuffle could not remove its saved queue. Please try again.")
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
        .sensoryFeedback(.selection, trigger: pinFeedbackTrigger)
        .sensoryFeedback(.impact(weight: .medium), trigger: removeFeedbackTrigger)
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

    @ViewBuilder
    private var emptyState: some View {
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

    /// Forgets the saved order behind the Continue card. Music keeps playing
    /// and the playlist itself is untouched; the next Play saves a new one.
    private func removeSavedQueue() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            showsRemoveQueueError = !generatedQueueSession.clearSavedQueue()
        }
        if !showsRemoveQueueError {
            removeFeedbackTrigger += 1
        }
    }

    private func pinButton(for playlist: LibraryPlaylist) -> some View {
        let isPinned = pinnedPlaylistStore.isPinned(playlist.persistentIDString)
        return Button {
            pinnedPlaylistStore.toggle(playlist.persistentIDString)
            pinFeedbackTrigger += 1
        } label: {
            Label(
                isPinned
                    ? String(localized: "Unpin Playlist")
                    : String(localized: "Pin Playlist"),
                systemImage: isPinned ? "pin.slash" : "pin.fill"
            )
        }
        .tint(Color.ember)
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
                    .foregroundStyle(Color.ember)
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
    @EnvironmentObject private var coverStore: PlaylistCoverStore
    @ObservedObject var viewModel: PlaylistViewModel
    let transition: Namespace.ID
    let open: () -> Void
    let remove: () -> Void

    private static let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    private var isLive: Bool {
        playbackService.generatedQueueProgress?.queueID == viewModel.queueID
    }

    /// The card is always dark so the field shows the playlist's colours at
    /// full depth, in light mode too.
    private var palette: ArtworkColorPalette {
        ArtworkPalette.palette(
            for: viewModel.playlist,
            coverSwatches: coverStore.covers[viewModel.playlist.id]?.swatches,
            appearance: .dark
        )
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
                            .tint(Color.ember)
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
                // Holds still inside the list: a drifting field would redraw
                // the row every frame while the list scrolls.
                ColorField(
                    palette: palette,
                    arrangement: fieldArrangement
                )
                .clipShape(Self.shape)
                .shadow(color: Color(palette.ground).opacity(0.3), radius: 16, y: 8)
            }
            .contentShape(Self.shape)
            .environment(\.colorScheme, .dark)
            .screenTheme(palette)
        }
        .buttonStyle(PressableButtonStyle())
        .contentShape(.contextMenuPreview, Self.shape)
        .contextMenu {
            Button("Remove", systemImage: "minus.circle", role: .destructive, action: remove)
        }
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens your most recent queue without changing its order")
        .accessibilityAction(named: "Remove", remove)
    }
}

/// Search that sits at the top of the list and scrolls away with it, like
/// the Music app's library. SwiftUI's own search drawer starts out hidden on
/// iOS 27, so the field lives in the list instead.
private struct PlaylistSearchField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search playlists", text: $text)
                    .focused(isFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .accessibilityAddTraits(.isSearchField)
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear Search")
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, text.isEmpty ? 12 : 0)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .contentShape(Capsule())
            .onTapGesture {
                isFocused.wrappedValue = true
            }

            if isFocused.wrappedValue {
                Button {
                    text = ""
                    isFocused.wrappedValue = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color(.tertiarySystemFill), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Cancel Search")
                .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(minHeight: 44)
        .animation(.smooth(duration: 0.25), value: isFocused.wrappedValue)
    }
}
