import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

struct PlaylistBrowserView: View {
    @Environment(\.editMode) private var editMode
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var pinnedPlaylistStore: PinnedPlaylistStore
    @EnvironmentObject private var generatedQueueSession: GeneratedQueueSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isCoveredBySheet) private var isCoveredBySheet
    @State private var scroll = ScrollTracker()
    @State private var searchText = ""
    @State private var showsSettings = false
    @State private var showsSavedQueue = false
    @Namespace private var playlistTransition
    @State private var showsRemoveQueueError = false
    @State private var removeFeedbackTrigger = 0
    @State private var pinFeedbackTrigger = 0

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingPlaylists: [LibraryPlaylist] {
        if trimmedSearch.isEmpty {
            return libraryService.playlists
        }

        return libraryService.playlists.filter {
            // Ignores case, accents, and full- versus half-width forms, so
            // "beyonce" finds "Beyoncé" and "ｒｏｃｋ" finds "Rock".
            $0.name.localizedStandardContains(trimmedSearch)
        }
    }

    private var availablePinnedPlaylists: [LibraryPlaylist] {
        let playlistsByID = Dictionary(
            uniqueKeysWithValues: libraryService.playlists.map { ($0.persistentIDString, $0) }
        )
        return pinnedPlaylistStore.pinnedPlaylistIDs.compactMap { playlistsByID[$0] }
    }

    /// The list's groups, worked out once per redraw. The library arrives
    /// sorted by name, and filtering keeps that order.
    private struct Sections {
        var pinned: [LibraryPlaylist] = []
        var withSongs: [LibraryPlaylist] = []
        /// Empty playlists wait at the bottom, so the list opens on music.
        var empty: [LibraryPlaylist] = []

        var isEmpty: Bool {
            pinned.isEmpty && withSongs.isEmpty && empty.isEmpty
        }
    }

    private var sections: Sections {
        let matching = matchingPlaylists
        let matchingIDs = Set(matching.map(\.id))
        let pinnedIDs = Set(pinnedPlaylistStore.pinnedPlaylistIDs)
        let unpinned = matching.filter { !pinnedIDs.contains($0.persistentIDString) }
        return Sections(
            pinned: availablePinnedPlaylists.filter { matchingIDs.contains($0.id) },
            withSongs: unpinned.filter { !$0.entries.isEmpty },
            empty: unpinned.filter(\.entries.isEmpty)
        )
    }

    /// The welcome screen's world: the app icon's ember and wine, so home
    /// feels like the same app as the first screen.
    private var palette: ArtworkColorPalette {
        ArtworkPalette.brand(appearance: .init(colorScheme))
    }

    private var canReorderPinnedPlaylists: Bool {
        trimmedSearch.isEmpty && availablePinnedPlaylists.count > 1
    }

    var body: some View {
        // The list stays on screen in every state, with loading and empty
        // states laid over it, so the title and search never jump.
        List {
            // The title scrolls away with the list and fades under the soft
            // top edge, like the Music app's Home, instead of collapsing
            // into the bar.
            titleRow(String(localized: "Playlists"), font: .largeTitle.bold(), top: 0, bottom: 8)

            if !libraryService.playlists.isEmpty {
                PlaylistSearchField(text: $searchText)
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

            let sections = sections

            // Titles are rows rather than section headers: a plain list pins
            // headers under the bar, where rows would scroll behind them on
            // the see-through page.
            if !sections.pinned.isEmpty {
                sectionTitle(String(localized: "Pinned"))
                ForEach(sections.pinned) { playlist in
                    playlistLink(for: playlist)
                }
                .onMove(perform: movePinnedPlaylists)
                .moveDisabled(!canReorderPinnedPlaylists)
            }

            if !sections.withSongs.isEmpty {
                if !sections.pinned.isEmpty {
                    sectionTitle(String(localized: "All Playlists"))
                }
                ForEach(sections.withSongs) { playlist in
                    playlistLink(for: playlist)
                }
            }

            if !sections.empty.isEmpty {
                if !sections.pinned.isEmpty || !sections.withSongs.isEmpty {
                    sectionTitle(String(localized: "Empty Playlists"))
                }
                ForEach(sections.empty) { playlist in
                    playlistLink(for: playlist)
                }
            }

            // Shown as a row so the search field above it stays usable.
            if !libraryService.playlists.isEmpty, sections.isEmpty {
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
        .softTopEdge()
        .tracksScrollOffset(in: scroll)
        .refreshable {
            libraryService.refreshPlaylists()
        }
        .overlay {
            emptyState
        }
        .background {
            BrowserBackdrop(palette: palette, scroll: scroll)
                .environment(\.isCoveredBySheet, isCoveredBySheet || showsSettings)
        }
        .screenTheme(palette)
        .navigationTitle("Playlists")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The visible title lives in the list; the bar keeps only its
            // buttons. The navigation title still names the screen for
            // VoiceOver and the app switcher.
            ToolbarItem(placement: .principal) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            }

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

    private func sectionTitle(_ title: String) -> some View {
        titleRow(title, font: .title3.bold(), top: 20, bottom: 4)
    }

    private func titleRow(_ title: String, font: Font, top: CGFloat, bottom: CGFloat) -> some View {
        Text(title)
            .font(font)
            .foregroundStyle(Color.primary)
            .accessibilityAddTraits(.isHeader)
            .listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .moveDisabled(true)
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
                isPinned: pinnedPlaylistStore.isPinned(playlist.persistentIDString),
                transition: playlistTransition
            )
        }
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.primary.opacity(0.1))
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
    private static let artworkSize: CGFloat = 56

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.screenTheme) private var theme
    let playlist: LibraryPlaylist
    let isPinned: Bool
    let transition: Namespace.ID

    private var isEmpty: Bool {
        playlist.entries.isEmpty
    }

    private var countText: String {
        isEmpty ? String(localized: "Empty") : localizedSongCount(playlist.entries.count)
    }

    /// The one thing worth knowing before opening: unplayed songs if there
    /// are any, otherwise overlooked ones.
    private var waiting: (text: String, kind: PlayFreshness)? {
        let insight = playlist.rediscoveryInsight
        if insight.unplayedCount > 0 {
            return (localizedUnplayedCount(insight.unplayedCount), .unplayed)
        }
        if insight.overlookedCount > 0 {
            return (localizedOverlookedCount(insight.overlookedCount), .overlooked)
        }
        return nil
    }

    private var detailLine: Text {
        let line = Text(countText).foregroundStyle(theme.secondaryText)
        guard let waiting else {
            return line
        }
        let symbol = waiting.kind.systemImage.map {
            Text(Image(systemName: $0)).foregroundStyle(Color.ember) + Text(verbatim: " ")
        } ?? Text(verbatim: "")
        return line
            + Text(verbatim: " · ").foregroundStyle(theme.secondaryText)
            + symbol
            + Text(waiting.text).foregroundStyle(Color.primary)
    }

    private var artwork: some View {
        PlaylistArtworkView(playlist: playlist, size: Self.artworkSize)
            .opacity(isEmpty ? 0.55 : 1)
            .zoomSource(id: playlist.id, in: transition, cornerRadius: artworkCornerRadius(for: Self.artworkSize))
    }

    private var titleAndDetail: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(playlist.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(isEmpty ? theme.secondaryText : Color.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

            detailLine
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private var pin: some View {
        if isPinned {
            Image(systemName: "pin.fill")
                .font(.footnote)
                .foregroundStyle(Color.ember)
                .accessibilityHidden(true)
        }
    }

    private var playlistAccessibilityLabel: String {
        var parts = [playlist.name, countText]
        if let waiting {
            parts.append(waiting.text)
        }
        if isPinned {
            parts.append(String(localized: "pinned"))
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
        Group {
            // At accessibility sizes the cover moves above the text, so the
            // name gets the row's full width instead of breaking every word.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        artwork
                        Spacer(minLength: 8)
                        pin
                    }
                    titleAndDetail
                }
            } else {
                HStack(spacing: 14) {
                    artwork
                    titleAndDetail
                    Spacer(minLength: 8)
                    pin
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(playlistAccessibilityLabel)
        .accessibilityHint(playlistAccessibilityHint)
    }
}

/// Entry point back into the most recent queue. It is glass over the page's
/// own colours, so it sits in the background rather than on top of it, in
/// light mode too; the artwork carries the playlist's colours.
private struct ContinueQueueCard: View {
    static let transitionID = "continueQueue"
    private static let artworkSize: CGFloat = 64

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.screenTheme) private var theme
    @EnvironmentObject private var playbackService: MusicPlaybackService
    @ObservedObject var viewModel: PlaylistViewModel
    let transition: Namespace.ID
    let open: () -> Void
    let remove: () -> Void

    private static let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    /// Offered from touch and hold and from the options button.
    private var removeButton: some View {
        Button("Remove", systemImage: "minus.circle", role: .destructive, action: remove)
    }

    private var isLive: Bool {
        playbackService.generatedQueueProgress?.queueID == viewModel.queueID
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
                PlaylistArtworkView(playlist: viewModel.playlist, size: Self.artworkSize)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
                    .zoomSource(id: Self.transitionID, in: transition, cornerRadius: artworkCornerRadius(for: Self.artworkSize))

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.playlist.name)
                        .font(.headline)
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    HStack(spacing: 6) {
                        if isLive {
                            NowPlayingIndicator(isPlaying: playbackService.isPlaying)
                        }
                        Text(detailText)
                            .foregroundStyle(theme.secondaryText)
                    }
                    .font(.subheadline)
                    if let progressFraction {
                        ProgressView(value: progressFraction)
                            .tint(Color.ember)
                            .padding(.top, 4)
                    }
                }

                Spacer(minLength: 4)

                // Room for the options button laid over the card.
                Color.clear
                    .frame(width: 32, height: 1)
            }
            .padding(14)
            .glassPane(in: Self.shape)
            .contentShape(Self.shape)
        }
        .buttonStyle(PressableButtonStyle())
        .contentShape(.contextMenuPreview, Self.shape)
        .contextMenu {
            removeButton
        }
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens your most recent queue without changing its order")
        .accessibilityAction(named: "Remove", remove)
        // A visible way to the card's actions; touch and hold still works.
        .overlay(alignment: .trailing) {
            Menu {
                removeButton
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.08), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .padding(.trailing, 10)
            .accessibilityLabel("More Options")
        }
    }
}

/// Search that sits at the top of the list and scrolls away with it, like
/// the Music app's library. SwiftUI's own search drawer starts out hidden on
/// iOS 27, so the field lives in the list instead.
private struct PlaylistSearchField: View {
    @Binding var text: String
    /// Focus stays inside the row on purpose. When the screen owned it, every
    /// focus change re-rendered the whole list, which reconfigured this row
    /// and snapped the close button's animation to its end.
    @FocusState private var isFocused: Bool
    /// Set once the screen is drawing again after the tap. Taking focus
    /// sets up the keyboard, which holds up drawing for 80–160ms, longest on
    /// the first tap; started by the tap itself, the animation ran unseen
    /// for that long and jumped.
    @State private var isActive = false
    @State private var nextFrame = NextSmoothFrame()

    var body: some View {
        HStack(spacing: 0) {
            field
            // The button fades in its place while the field narrows to make
            // room. It stays in the layout so the resize can't be skipped.
            closeButton
                .padding(.leading, 8)
                .frame(width: isActive ? 52 : 0, alignment: .trailing)
                .allowsHitTesting(isActive)
                .accessibilityHidden(!isActive)
        }
        .frame(minHeight: 44)
        .animation(.smooth(duration: 0.25), value: isActive)
        .onChange(of: isFocused) { _, isFocused in
            if isFocused {
                activate()
            } else {
                nextFrame.cancel()
                isActive = false
            }
        }
        .task(id: isActive) {
            // A tap that never turned into focus doesn't leave the button up.
            guard isActive, !isFocused else {
                return
            }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled, !isFocused {
                isActive = false
            }
        }
    }

    private var field: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search playlists", text: $text)
                .focused($isFocused)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        activate()
                    }
                )
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
        .background {
            // The clear button handles its own taps.
            MovingListTapCatcher(skipsTrailingWidth: text.isEmpty ? 0 : 44) {
                activate()
                isFocused = true
            }
        }
        .searchGlass(in: Capsule())
        .contentShape(Capsule())
        .onTapGesture {
            activate()
            isFocused = true
        }
    }

    private func activate() {
        nextFrame.run {
            // Changed from a frame callback, the `.animation` modifier let
            // it jump, so it is animated here.
            withAnimation(.smooth(duration: 0.25)) {
                isActive = true
            }
        }
    }

    private var closeButton: some View {
        Button {
            text = ""
            // The button hides once focus has gone, in an update of its own:
            // hidden together with the focus change, its fade was cut short.
            if isFocused {
                isFocused = false
            } else {
                nextFrame.cancel()
                isActive = false
            }
        } label: {
            Image(systemName: "xmark")
                .font(.body.weight(.medium))
                // Bar buttons stop growing at the largest standard size and
                // offer the large content viewer instead.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(.primary)
                .opacity(isActive ? 1 : 0)
                .frame(width: 36, height: 36)
                .searchGlass(in: Circle(), isVisible: isActive)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        // The interactive glass gives the press feedback.
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel Search")
        .accessibilityShowsLargeContentViewer()
    }
}

/// Catches a tap on the search field that lands while the list is still
/// gliding or bouncing back to the top, and calls `onTap` for it.
///
/// A touch on a moving scroll view only stops the scroll and never reaches
/// the content: the field's interactive glass lights up on touch-down, but
/// neither its tap gesture nor the text field sees the tap. Bouncing back
/// into place has a long, almost invisible tail, so the list looks still
/// while it is still moving, and the field seemed to ignore taps after any
/// scroll back to the top. At rest this does nothing, and the field's own
/// tap handling stays in charge.
private struct MovingListTapCatcher: UIViewRepresentable {
    /// Width at the field's trailing edge to leave alone, such as a button.
    var skipsTrailingWidth: CGFloat
    let onTap: () -> Void

    func makeUIView(context: Context) -> MovingListTapCatcherView {
        let view = MovingListTapCatcherView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: MovingListTapCatcherView, context: Context) {
        view.skipsTrailingWidth = skipsTrailingWidth
        view.onTap = onTap
    }

    static func dismantleUIView(_ view: MovingListTapCatcherView, coordinator: ()) {
        view.stopWatching()
    }
}

/// Sits behind the field, matching its frame, and watches its window's
/// touches while it is in one.
private final class MovingListTapCatcherView: UIView {
    var skipsTrailingWidth: CGFloat = 0
    var onTap: (() -> Void)?
    private var watcher: MovingListTapWatcher?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        stopWatching()
        if let window {
            let watcher = MovingListTapWatcher(field: self)
            window.addGestureRecognizer(watcher)
            self.watcher = watcher
        }
    }

    func stopWatching() {
        if let watcher {
            watcher.view?.removeGestureRecognizer(watcher)
        }
        watcher = nil
    }

    /// The list the field scrolls with, when it is gliding or bouncing.
    func movingScrollView() -> UIScrollView? {
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? UIScrollView {
                return isMoving(scrollView) ? scrollView : nil
            }
            ancestor = view.superview
        }
        return nil
    }

    private func isMoving(_ scrollView: UIScrollView) -> Bool {
        if scrollView.isDecelerating {
            return true
        }
        // Bouncing back from a pull past either end.
        let inset = scrollView.adjustedContentInset
        let offset = scrollView.contentOffset.y
        let top = -inset.top
        let bottom = max(top, scrollView.contentSize.height + inset.bottom - scrollView.bounds.height)
        return offset < top - 0.5 || offset > bottom + 0.5
    }

    /// Whether a point, in this view's coordinates, is on the field's own
    /// text area.
    func isOnField(_ point: CGPoint) -> Bool {
        var area = bounds
        area.size.width -= min(skipsTrailingWidth, area.width)
        if effectiveUserInterfaceLayoutDirection == .rightToLeft {
            area.origin.x = bounds.maxX - area.width
        }
        return area.contains(point)
    }
}

/// Follows one finger from touch-down to lift without ever taking the touch
/// from anything, and reports a short, still tap on the field that began
/// while its list was moving.
@MainActor
private final class MovingListTapWatcher: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private static let maxDuration: TimeInterval = 0.5
    private static let maxMovement: CGFloat = 10

    private weak var field: MovingListTapCatcherView?
    /// The field's list if it was moving as the finger landed. Read before
    /// any gesture sees the touch, since the list stops once one does.
    private weak var movingScrollView: UIScrollView?
    private var start: (location: CGPoint, time: TimeInterval)?

    init(field: MovingListTapCatcherView) {
        self.field = field
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard start == nil,
              touches.count == 1,
              event.allTouches?.count == 1,
              let touch = touches.first,
              let window = view as? UIWindow,
              let field,
              field.window === window,
              let scrollView = movingScrollView ?? field.movingScrollView(),
              field.isOnField(touch.location(in: field)),
              // Something covering the field, such as a sheet or a pushed
              // playlist, keeps the touch.
              window.hitTest(touch.location(in: window), with: event)?
                  .isDescendant(of: scrollView) == true else {
            state = .failed
            return
        }
        start = (touch.location(in: window), touch.timestamp)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first, isStill(touch) else {
            state = .failed
            return
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        if let touch = touches.first,
           isStill(touch),
           let field,
           field.isOnField(touch.location(in: field)) {
            // After the touch has finished, so the list has stopped first.
            DispatchQueue.main.async { [weak field] in
                field?.onTap?()
            }
        }
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .failed
    }

    override func reset() {
        super.reset()
        start = nil
        movingScrollView = nil
    }

    private func isStill(_ touch: UITouch) -> Bool {
        guard let start, let window = view else {
            return false
        }
        let location = touch.location(in: window)
        return touch.timestamp - start.time <= Self.maxDuration
            && hypot(location.x - start.location.x, location.y - start.location.y) <= Self.maxMovement
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if start == nil {
            movingScrollView = field?.movingScrollView()
        }
        return true
    }

    func gestureRecognizer(
        _ gesture: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

/// Runs work once frames arrive on time again, so an animation it starts
/// is seen from its first frame. Whatever holds up drawing can do so in
/// several stretches, such as the keyboard being set up, so a single frame
/// between them doesn't count. It gives up waiting after half a second.
@MainActor
private final class NextSmoothFrame: NSObject {
    private var link: CADisplayLink?
    private var work: (() -> Void)?
    private var lastFrame: CFTimeInterval?
    private var deadline: CFTimeInterval = 0

    func run(_ work: @escaping () -> Void) {
        self.work = work
        guard link == nil else {
            return
        }
        lastFrame = nil
        deadline = CACurrentMediaTime() + 0.5
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func cancel() {
        link?.invalidate()
        link = nil
        work = nil
    }

    @objc private func frame(_ link: CADisplayLink) {
        let interval = link.targetTimestamp - link.timestamp
        let isOnTime = lastFrame.map { link.timestamp - $0 < interval * 1.5 } ?? false
        lastFrame = link.timestamp
        guard isOnTime || link.timestamp > deadline else {
            return
        }
        let work = work
        cancel()
        work?()
    }
}

/// The welcome screen's colour field behind the Playlists header. It drifts
/// only while music plays, and watches playback itself so updates redraw
/// the field rather than the whole list.
private struct BrowserBackdrop: View {
    @EnvironmentObject private var playbackService: MusicPlaybackService
    let palette: ArtworkColorPalette
    let scroll: ScrollTracker

    var body: some View {
        ScrollingFieldBackdrop(
            palette: palette,
            arrangement: 0,
            isPlaying: playbackService.isPlaying,
            fieldHeight: 460,
            scroll: scroll
        )
    }
}

private extension View {
    /// The progressive blur iOS 26 uses at the top of Music's Home, so
    /// content fades out under the bar rather than meeting a hard edge.
    @ViewBuilder
    func softTopEdge() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }

    /// Liquid Glass on iOS 26 and later, so the page's colours show through
    /// as they do behind the system's own search fields; a plain fill before.
    @ViewBuilder
    func searchGlass(in shape: some Shape, isVisible: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            // Interactive glass answers the moment a finger lands, before
            // the keyboard has been set up, like the system's own controls.
            // Glass ignores opacity set around it once pressed, so it fades
            // through `.identity` instead.
            glassEffect(isVisible ? .regular.interactive() : .identity, in: shape)
        } else {
            background(Color(.tertiarySystemFill).opacity(isVisible ? 1 : 0), in: shape)
        }
    }
}

