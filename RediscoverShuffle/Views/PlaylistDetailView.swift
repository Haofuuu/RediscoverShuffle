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
    @Environment(\.playlistPage) private var page
    @EnvironmentObject private var playbackService: MusicPlaybackService
    @EnvironmentObject private var pinnedPlaylistStore: PinnedPlaylistStore
    @EnvironmentObject private var generatedQueueSession: GeneratedQueueSession
    @EnvironmentObject private var coverStore: PlaylistCoverStore
    @AppStorage(SettingsKeys.rediscoveryStrength) private var rediscoveryStrength = RediscoveryStrengthSetting.defaultValue
    @AppStorage(SettingsKeys.playlistSongSortOption) private var songSortRawValue = PlaylistSongSortOption.defaultValue.rawValue
    @AppStorage(SettingsKeys.showPlayCounts) private var showPlayCounts = AppSettingDefaults.showPlayCounts
    @ScaledMetric(relativeTo: .title) private var heroArtworkSize = 236
    @ObservedObject private var viewModel: PlaylistViewModel
    @State private var listMode = ListMode.upNext
    @State private var scroll = ScrollTracker()
    @State private var headerHeight: CGFloat = 540
    @State private var topBarBottom: CGFloat = 100
    @State private var showsBarTitle = false
    @State private var playFeedbackTrigger = 0
    @State private var reshuffleFeedbackTrigger = 0
    @State private var showsRediscoveryInfo = false
    /// The order Music was playing when this one was reshuffled, so the
    /// screen can say the new order isn't playing until Play is tapped.
    @State private var queuePlayingBeforeReshuffle: UUID?

    /// Shows a playlist's order. The page stage that opens the screen owns
    /// the order, so a page that comes back shows the one it left with.
    init(viewModel: PlaylistViewModel) {
        self.viewModel = viewModel
    }

    /// A fresh preview order for a playlist that has no saved queue.
    static func previewQueue(for playlist: LibraryPlaylist) -> PlaylistViewModel {
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
                fieldHeight: topBarBottom + headerHeight + 32,
                scroll: scroll
            )
        }
        .screenTheme(palette)
        .onGeometryChange(for: CGFloat.self) { proxy in
            // The list runs up under the top bar, which it sees as part of
            // its safe area.
            proxy.safeAreaInsets.top
        } action: { newValue in
            topBarBottom = newValue
        }
        .topBar(scroll: scroll, isOverTitle: showsBarTitle) {
            topBar
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: playFeedbackTrigger)
        .sensoryFeedback(.impact(weight: .light), trigger: reshuffleFeedbackTrigger)
        .onAppear {
            rediscoveryStrength = normalizedStrength
            songSortRawValue = songSortOption.rawValue
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

    // MARK: Top bar

    /// Back, the playlist's name once the large one has scrolled away, and
    /// the pin. The page is moved by the page stage rather than pushed on a
    /// navigation stack, so it draws its own bar.
    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                page?.goBack()
            } label: {
                Image(systemName: "chevron.backward")
                    .barButtonLabel()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary)
            .accessibilityLabel("Back")

            Text(viewModel.playlist.name)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .opacity(showsBarTitle ? 1 : 0)
                .accessibilityHidden(!showsBarTitle)

            pinButton
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private var pinButton: some View {
        let isPinned = pinnedPlaylistStore.isPinned(viewModel.playlist.persistentIDString)
        return Button {
            pinnedPlaylistStore.toggle(viewModel.playlist.persistentIDString)
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .barButtonLabel()
        }
        .buttonStyle(.plain)
        // The ember marks a pinned playlist; unpinned it matches the back
        // button, which also keeps it clear on deep artwork colours.
        .foregroundStyle(isPinned ? Color.ember : Color.primary)
        .accessibilityLabel(isPinned ? String(localized: "Unpin Playlist") : String(localized: "Pin Playlist"))
        .sensoryFeedback(.selection, trigger: isPinned)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 18) {
            PlaylistArtworkView(playlist: viewModel.playlist, size: min(heroArtworkSize, 300))
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .playlistPage)
                } action: { frame in
                    page?.coverFrame = frame
                }
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
                        proxy.frame(in: .playlistPage).maxY < topBarBottom
                    } action: { isHidden in
                        withAnimation(.strongEaseOut(duration: 0.16)) {
                            showsBarTitle = isHidden
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
                .presentationCompactAdaptation(.popover)
                .frostedPopoverBackground()
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
        // Plain primary and secondary label colours on the frosted
        // background, never vibrant or artwork-tinted ones.
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

/// The bar's material before iOS 26: clear over the header at rest, like a
/// navigation bar's, and filled once rows scroll beneath. It reads the
/// scroll position itself, so scrolling redraws only the bar's background.
private struct BarMaterial: View {
    let scroll: ScrollTracker
    /// iOS 17 can't read the scroll position; there the bar fills once the
    /// playlist's name has scrolled under it.
    let isOverTitle: Bool

    var body: some View {
        let isFilled = scroll.offset > 1 || isOverTitle
        Rectangle()
            .fill(.bar)
            .ignoresSafeArea(edges: .top)
            .opacity(isFilled ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: isFilled)
    }
}

private extension View {
    /// Pins a bar to the top of the page. On iOS 26 and later the list
    /// fades beneath it under the system's scroll edge effect; before, the
    /// bar gains the system's bar material once the list has scrolled.
    @ViewBuilder
    func topBar<Content: View>(
        scroll: ScrollTracker,
        isOverTitle: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .top, spacing: 0, content: content)
        } else {
            safeAreaInset(edge: .top, spacing: 0) {
                content()
                    .background {
                        BarMaterial(scroll: scroll, isOverTitle: isOverTitle)
                    }
            }
        }
    }

    /// A bar button's symbol in a full-size target: on Liquid Glass from
    /// iOS 26, as the system's own bar buttons are, and bare before. The
    /// symbol is drawn over the glass, never through it, so it shrinks with
    /// the page while a swipe back holds it.
    @ViewBuilder
    func barButtonLabel() -> some View {
        let symbol = font(.body.weight(.medium))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        if #available(iOS 26.0, *) {
            symbol.background {
                Color.clear
                    .glassEffect(.regular.interactive(), in: Circle())
            }
        } else {
            symbol
        }
    }

    /// A thin frosted material on every iOS version, in place of the Liquid
    /// Glass iOS 26 and later give popovers on their own. The popover sits
    /// over a vivid artwork-coloured field, and through clear glass the
    /// playlist's title and Play button showed plainly behind the text.
    /// The material blurs them into a soft tint of the artwork's colour, so
    /// the popover stays light and translucent but reads cleanly. It
    /// follows light and dark mode, and `.primary` and `.secondary` text
    /// keep their contrast on it.
    func frostedPopoverBackground() -> some View {
        presentationBackground(.thinMaterial)
    }
}
