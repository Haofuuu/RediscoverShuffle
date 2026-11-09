import SwiftUI

/// One screen for a playlist: its cover, a ready-made rediscovery order, and
/// the controls to play or reshuffle it. The order shown is the order played.
struct PlaylistDetailView: View {
    private enum ListMode: Hashable {
        case upNext
        case allSongs
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenArrival) private var screenArrival
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playbackService: MusicPlaybackService
    @EnvironmentObject private var pinnedPlaylistStore: PinnedPlaylistStore
    @EnvironmentObject private var generatedQueueSession: GeneratedQueueSession
    @EnvironmentObject private var coverStore: PlaylistCoverStore
    @AppStorage(SettingsKeys.rediscoveryStrength) private var rediscoveryStrength = RediscoveryStrengthSetting.defaultValue
    @AppStorage(SettingsKeys.playlistSongSortOption) private var songSortRawValue = PlaylistSongSortOption.defaultValue.rawValue
    @AppStorage(SettingsKeys.showPlayCounts) private var showPlayCounts = AppSettingDefaults.showPlayCounts
    @ScaledMetric(relativeTo: .title) private var heroArtworkSize = 236
    @StateObject private var viewModel: PlaylistViewModel
    @State private var listMode = ListMode.upNext
    @State private var scroll = ScrollTracker()
    @State private var headerHeight: CGFloat = 540
    @State private var navigationBarBottom: CGFloat = 100
    @State private var showsNavigationTitle = false
    @State private var playFeedbackTrigger = 0
    @State private var reshuffleFeedbackTrigger = 0
    @State private var showsRediscoveryInfo = false
    /// The order Music was playing when this one was reshuffled, so the
    /// screen can say the new order isn't playing until Play is tapped.
    @State private var queuePlayingBeforeReshuffle: UUID?

    /// Opens a playlist. Pass the saved queue when it belongs to this playlist
    /// so its order and live progress carry over; otherwise a fresh preview
    /// order is generated immediately.
    init(playlist: LibraryPlaylist, savedQueue: PlaylistViewModel? = nil) {
        _viewModel = StateObject(
            wrappedValue: savedQueue
                ?? ReturningPage.take(for: playlist)
                ?? Self.previewQueue(for: playlist)
        )
    }

    private static func previewQueue(for playlist: LibraryPlaylist) -> PlaylistViewModel {
        let viewModel = PlaylistViewModel(playlist: playlist)
        let storedStrength = UserDefaults.standard.object(forKey: SettingsKeys.rediscoveryStrength) as? Double
        viewModel.reshuffle(
            bias: RediscoveryStrengthSetting.normalized(storedStrength ?? RediscoveryStrengthSetting.defaultValue)
        )
        return viewModel
    }

    var body: some View {
        List {
            header
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    headerHeight = height
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if viewModel.playlist.entries.isEmpty {
                ContentUnavailableView(
                    "Empty Playlist",
                    systemImage: "music.note",
                    description: Text("Add songs to this playlist in the Music app.")
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                Section {
                    rows
                } header: {
                    sectionHeader
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .tracksScrollOffset(in: scroll)
        .background {
            ScrollingFieldBackdrop(
                palette: palette,
                arrangement: fieldArrangement,
                isPlaying: isFollowingLiveQueue && playbackService.isPlaying,
                fieldHeight: navigationBarBottom + headerHeight + 32,
                scroll: scroll
            )
        }
        .screenTheme(palette)
        .onGeometryChange(for: CGFloat.self) { proxy in
            // Depending on the OS, the list either starts below the bar or
            // reports the bar as a safe-area inset; either value is its bottom.
            max(proxy.frame(in: .global).minY, proxy.safeAreaInsets.top)
        } action: { newValue in
            navigationBarBottom = newValue
        }
        .navigationTitle(viewModel.playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(viewModel.playlist.name)
                    .font(.headline)
                    .lineLimit(1)
                    .opacity(showsNavigationTitle ? 1 : 0)
                    .accessibilityHidden(!showsNavigationTitle)
            }
            ToolbarItem(placement: .topBarTrailing) {
                pinButton
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: playFeedbackTrigger)
        .sensoryFeedback(.impact(weight: .light), trigger: reshuffleFeedbackTrigger)
        .onAppear {
            rediscoveryStrength = normalizedStrength
            songSortRawValue = songSortOption.rawValue
            screenArrival?.goBack = { [dismiss] animated in
                guard !animated else {
                    dismiss()
                    return
                }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dismiss()
                }
            }
            screenArrival?.onDeparture = { [viewModel] departure in
                switch departure {
                case .started: ReturningPage.remember(viewModel)
                case .finished: ReturningPage.gone(viewModel)
                }
            }
        }
        .onChange(of: rediscoveryStrength) { oldValue, newValue in
            // A new strength previews immediately, but never disturbs a queue
            // that is currently playing in Music.
            guard RediscoveryStrengthSetting.normalized(oldValue) != RediscoveryStrengthSetting.normalized(newValue),
                  !isFollowingLiveQueue else {
                return
            }
            reshuffle()
        }
        .alert("Playback Problem", isPresented: playbackErrorIsPresented) {
            Button("Skip Song and Continue") {
                playbackService.skipUnavailableItemAndContinue()
            }
            Button("Dismiss", role: .cancel) {
                playbackService.dismissPlaybackError()
            }
        } message: {
            Text(playbackService.errorMessage ?? String(localized: "Music couldn’t start this queue."))
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 18) {
            PlaylistArtworkView(playlist: viewModel.playlist, size: min(heroArtworkSize, 300))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.24), radius: 28, y: 16)
                .padding(.top, 12)

            VStack(spacing: 6) {
                Text(viewModel.playlist.name)
                    .font(.title.weight(.bold))
                    .fontWidth(.expanded)
                    .tracking(-0.5)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .onGeometryChange(for: Bool.self) { proxy in
                        proxy.frame(in: .global).maxY < navigationBarBottom
                    } action: { isHidden in
                        withAnimation(.strongEaseOut(duration: 0.16)) {
                            showsNavigationTitle = isHidden
                        }
                    }

                rediscoverySummary
            }

            actionButtons
                .padding(.top, 4)

            VStack(spacing: 6) {
                rediscoveryMenu
                if let queueCaption {
                    Text(queueCaption)
                        .font(.footnote)
                        .foregroundStyle(Color(palette.secondaryText))
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.25), value: queueCaption)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }

    /// The song count and what's waiting to be rediscovered. When there is
    /// something waiting, the ⓘ beside it explains what the words mean.
    @ViewBuilder
    private var rediscoverySummary: some View {
        if viewModel.playlist.rediscoveryInsight.isEmpty {
            headerSubtitle
                .font(.subheadline)
                .multilineTextAlignment(.center)
        } else {
            // The ⓘ keeps a full-size target, pulled in so it sits as close
            // to the words as a space would.
            HStack(spacing: -8) {
                headerSubtitle
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                rediscoveryInfoButton
            }
            .frame(minHeight: 44)
        }
    }

    private var rediscoveryInfoButton: some View {
        Button {
            // iOS holds a popover requested mid-transition and shows it
            // afterwards, over whatever screen is then on top.
            guard !isLeaving else {
                return
            }
            showsRediscoveryInfo = true
        } label: {
            Image(systemName: "info.circle")
                .font(.subheadline)
                .foregroundStyle(Color(palette.secondaryText))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How Rediscovery Works")
        .accessibilityHint("Explains unplayed and overlooked songs")
        .popover(isPresented: $showsRediscoveryInfo) {
            RediscoveryInfoView()
                .onAppear {
                    // The last guard: an explanation that belongs to a
                    // screen that has gone never stays over the next one.
                    if isLeaving {
                        showsRediscoveryInfo = false
                    }
                }
                .presentationCompactAdaptation(.popover)
                .opaquePopoverBackground()
        }
    }

    /// Says what Rediscovery and Reshuffle will do while Music is playing:
    /// the order on screen and the one playing can differ.
    private var queueCaption: String? {
        if isFollowingLiveQueue {
            return String(localized: "Changes take effect on your next Reshuffle.")
        }
        if let queuePlayingBeforeReshuffle,
           playbackService.generatedQueueProgress?.queueID == queuePlayingBeforeReshuffle {
            return String(localized: "New order, not playing yet. Tap Play to start it.")
        }
        return nil
    }

    private var headerSubtitle: Text {
        let secondary = Color(palette.secondaryText)
        let songs = Text(localizedSongCount(viewModel.playlist.entries.count))
            .foregroundStyle(secondary)
        guard let summary = localizedRediscoverySummary(viewModel.playlist.rediscoveryInsight) else {
            return songs
        }
        return songs
            + Text(verbatim: " · ").foregroundStyle(secondary)
            + Text(summary).foregroundStyle(Color.primary).fontWeight(.semibold)
    }

    private var actionButtons: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))

        return layout {
            primaryPlaybackButton

            Button(action: reshuffle) {
                HStack(spacing: 8) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: "shuffle")
                            .symbolEffect(.bounce, value: reduceMotion ? 0 : reshuffleFeedbackTrigger)
                            .accessibilityHidden(true)
                    }
                    Text("Reshuffle")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 22)
            }
            .buttonStyle(PrimaryActionButtonStyle(prominence: .tinted))
            .disabled(playbackService.isPreparing || viewModel.playlist.entries.isEmpty)
            .accessibilityHint("Creates a new order without changing what Music is playing")
        }
    }

    @ViewBuilder
    private var primaryPlaybackButton: some View {
        if isFollowingLiveQueue {
            Button(action: playbackService.togglePlayPause) {
                CenteredActionLabel(
                    title: playbackService.isPlaying
                        ? String(localized: "Pause")
                        : String(localized: "Resume"),
                    systemImage: playbackService.isPlaying ? "pause.fill" : "play.fill"
                )
            }
            .buttonStyle(PrimaryActionButtonStyle())
        } else {
            Button(action: play) {
                CenteredActionLabel(
                    title: playbackService.isPreparing
                        ? String(localized: "Starting…")
                        : String(localized: "Play"),
                    systemImage: "play.fill",
                    isLoading: playbackService.isPreparing
                )
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(playbackService.isPreparing || viewModel.visibleGeneratedOrder.isEmpty)
            .accessibilityHint("Plays this order in the Music app")
        }
    }

    private var rediscoveryMenu: some View {
        Menu {
            Section("Rediscovery decides how strongly less-played songs lead each new order.") {
                Picker("Rediscovery", selection: strengthBinding) {
                    ForEach(RediscoveryStrengthSetting.allowedValues, id: \.self) { value in
                        Text(RediscoveryStrengthSetting.name(for: Double(value)))
                            .tag(value)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.ember)
                Text(
                    String(
                        format: String(localized: "Rediscovery: %@"),
                        locale: .current,
                        strengthName
                    )
                )
                .foregroundStyle(Color.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(Color(palette.secondaryText))
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Rediscovery strength")
        .accessibilityValue(strengthName)
        .accessibilityHint("Chooses how strongly less-played songs lead the order")
    }

    /// Read when a button is tapped, so it holds even while SwiftUI has
    /// stopped updating this screen. True once the screen is grabbed to be
    /// swiped away or starts going away; the zoom transition's guard also
    /// switches its touches off in UIKit, which the toolbar sits outside.
    private var isLeaving: Bool {
        screenArrival?.isSettled == false
    }

    private var pinButton: some View {
        let isPinned = pinnedPlaylistStore.isPinned(viewModel.playlist.persistentIDString)
        return Button {
            guard !isLeaving else {
                return
            }
            pinnedPlaylistStore.toggle(viewModel.playlist.persistentIDString)
        } label: {
            Label(
                isPinned ? String(localized: "Unpin Playlist") : String(localized: "Pin Playlist"),
                systemImage: isPinned ? "pin.fill" : "pin"
            )
        }
        // The ember marks a pinned playlist; unpinned it matches the back
        // button, which also keeps it clear on deep artwork colours.
        .tint(isPinned ? Color.ember : Color.primary)
        .sensoryFeedback(.selection, trigger: isPinned)
    }

    // MARK: Song list

    private var sectionHeader: some View {
        HStack(spacing: 12) {
            listModePicker

            if listMode == .allSongs {
                Menu {
                    Picker("Sort Songs", selection: songSortBinding) {
                        ForEach(PlaylistSongSortOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.body.weight(.medium))
                        .frame(minWidth: 44, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Sort Songs")
                .accessibilityValue(songSortOption.title)
            }
        }
        .padding(.vertical, 6)
        .textCase(nil)
    }

    /// The system's segmented control before iOS 26; from iOS 26 one drawn
    /// in SwiftUI, because the system's glass one draws its selected label
    /// twice while a swipe back shrinks the page.
    @ViewBuilder
    private var listModePicker: some View {
        let selection = $listMode.animation(.strongEaseOut(duration: 0.2))
        if #available(iOS 26.0, *) {
            SegmentedSwitcher(
                title: "Show",
                selection: selection,
                options: [
                    (value: .upNext, label: Text("Up Next")),
                    (value: .allSongs, label: Text("All Songs")),
                ]
            )
        } else {
            Picker("Show", selection: selection) {
                Text("Up Next").tag(ListMode.upNext)
                Text("All Songs").tag(ListMode.allSongs)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var rows: some View {
        switch listMode {
        case .upNext:
            let entries = viewModel.visibleGeneratedOrder
            if entries.isEmpty {
                ContentUnavailableView(
                    "Queue Complete",
                    systemImage: "checkmark.circle",
                    description: Text("Reshuffle to start a new order.")
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                    let isCurrent = liveProgress?.isCurrentEntryVisible == true && offset == 0
                    TrackRow(
                        entry: entry,
                        position: offset + 1,
                        isCurrent: isCurrent,
                        isPlaying: playbackService.isPlaying,
                        freshness: viewModel.playlist.rediscoveryInsight.freshness(forPlayCount: entry.playCount),
                        showPlayCount: showPlayCounts
                    )
                    .listRowBackground(isCurrent ? Color.primary.opacity(0.08) : Color.clear)
                    .listRowSeparatorTint(Color.primary.opacity(0.1))
                }
            }
        case .allSongs:
            ForEach(sortedPlaylistEntries) { entry in
                TrackRow(
                    entry: entry,
                    freshness: viewModel.playlist.rediscoveryInsight.freshness(forPlayCount: entry.playCount),
                    showPlayCount: showPlayCounts
                )
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Color.primary.opacity(0.1))
            }
        }
    }

    // MARK: Actions

    private func play() {
        guard viewModel.prepareVisibleOrderForPlayback() else {
            return
        }
        queuePlayingBeforeReshuffle = nil
        generatedQueueSession.markSubmittedForPlayback(viewModel)
        playbackService.setQueueAndPlay(entries: viewModel.generatedOrder, queueID: viewModel.queueID)
        playFeedbackTrigger += 1
    }

    private func reshuffle() {
        if isFollowingLiveQueue {
            queuePlayingBeforeReshuffle = viewModel.queueID
        }
        // Rows glide to their new places; with Reduce Motion they swap in place.
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
            viewModel.reshuffle(bias: normalizedStrength)
            listMode = .upNext
        }
        // Keep the saved queue in sync only when this is that queue; browsing
        // another playlist's preview never replaces it.
        if generatedQueueSession.lastQueueViewModel === viewModel {
            generatedQueueSession.remember(viewModel)
        }
        reshuffleFeedbackTrigger += 1
    }

    // MARK: State

    private var palette: ArtworkColorPalette {
        ArtworkPalette.palette(
            for: viewModel.playlist,
            coverSwatches: coverStore.covers[viewModel.playlist.id]?.swatches,
            appearance: .init(colorScheme)
        )
    }

    /// Each generated order has its own layout of the playlist's colours, so
    /// a reshuffle visibly deals the field again and a saved queue keeps its look.
    private var fieldArrangement: Int {
        let id = viewModel.queueID.uuid
        return Int(id.0) << 8 | Int(id.1)
    }

    private var liveProgress: GeneratedQueuePlaybackProgress? {
        guard let progress = playbackService.generatedQueueProgress,
              progress.queueID == viewModel.queueID else {
            return nil
        }
        return progress
    }

    private var isFollowingLiveQueue: Bool {
        liveProgress != nil
    }

    private var normalizedStrength: Double {
        RediscoveryStrengthSetting.normalized(rediscoveryStrength)
    }

    private var strengthBinding: Binding<Int> {
        Binding(
            get: { Int(normalizedStrength) },
            set: { rediscoveryStrength = Double($0) }
        )
    }

    private var strengthName: String {
        RediscoveryStrengthSetting.name(for: normalizedStrength)
    }

    private var songSortOption: PlaylistSongSortOption {
        PlaylistSongSortOption.resolved(rawValue: songSortRawValue)
    }

    private var songSortBinding: Binding<PlaylistSongSortOption> {
        Binding(
            get: { songSortOption },
            set: { songSortRawValue = $0.rawValue }
        )
    }

    private var sortedPlaylistEntries: [PlaylistEntry] {
        songSortOption.sorted(viewModel.playlist.entries) {
            PlaylistSongSortValue(
                originalIndex: $0.originalIndex,
                playCount: $0.playCount,
                artist: $0.artist,
                title: $0.title
            )
        }
    }

    private var playbackErrorIsPresented: Binding<Bool> {
        Binding(
            get: { playbackService.errorMessage != nil },
            set: { if !$0 { playbackService.errorMessage = nil } }
        )
    }
}

/// What the rediscovery words mean, opened from a playlist's song count.
/// The page of a playlist that's going away. Tapping that playlist again
/// while it zooms back opens a new screen, and without this it would arrive
/// freshly shuffled; with it, the same page comes straight back.
@MainActor
private enum ReturningPage {
    private static var page: (viewModel: PlaylistViewModel, until: Date)?

    /// Kept while the playlist zooms back, however long a swipe takes,
    /// within a limit in case the end is never reported.
    static func remember(_ viewModel: PlaylistViewModel) {
        page = (viewModel, .now.addingTimeInterval(5))
    }

    /// Once it has gone, a tap that just missed the zoom still brings it back.
    static func gone(_ viewModel: PlaylistViewModel) {
        guard let page, page.viewModel === viewModel else {
            return
        }
        self.page = (viewModel, min(page.until, .now.addingTimeInterval(0.5)))
    }

    static func take(for playlist: LibraryPlaylist) -> PlaylistViewModel? {
        defer {
            page = nil
        }
        guard let page, page.viewModel.playlist.id == playlist.id, page.until > .now else {
            return nil
        }
        return page.viewModel
    }
}

private struct RediscoveryInfoView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How Rediscovery Works")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            term(
                PlayFreshness.unplayed.title ?? "",
                systemImage: PlayFreshness.unplayed.systemImage,
                definition: String(localized: "Songs you’ve never played.")
            )
            term(
                PlayFreshness.overlooked.title ?? "",
                systemImage: PlayFreshness.overlooked.systemImage,
                definition: String(localized: "Played, but no more than a quarter as often as this playlist’s typical song.")
            )
            term(
                String(localized: "Rediscovery"),
                systemImage: "sparkles",
                definition: String(localized: "Rediscovery decides how strongly less-played songs lead each new order.")
                    + " " + String(localized: "Every order is still random.")
            )
        }
        .padding(20)
        .frame(idealWidth: 320, maxWidth: 360, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        // Plain primary and secondary label colours against the opaque
        // background below, never vibrant or artwork-tinted ones.
        .foregroundStyle(.primary)
    }

    private func term(_ title: String, systemImage: String?, definition: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(Color.ember)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            Text(definition)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// An opaque system background on every iOS version, replacing the
    /// Liquid Glass iOS 26 and later give popovers on their own and any
    /// see-through material. The popover sits over a vivid, often dark,
    /// artwork-coloured field, and through glass that field's colours
    /// washed out the explanation's text. `systemBackground` adapts to
    /// light and dark mode and, as a popover is an elevated presentation,
    /// resolves to the elevated grey in dark mode, so `.primary` and
    /// `.secondary` text keep their full contrast whatever the artwork.
    func opaquePopoverBackground() -> some View {
        presentationBackground(Color(.systemBackground))
    }
}
