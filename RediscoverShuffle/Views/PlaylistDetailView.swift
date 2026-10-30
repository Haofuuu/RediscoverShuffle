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
    @EnvironmentObject private var playbackService: MusicPlaybackService
    @EnvironmentObject private var pinnedPlaylistStore: PinnedPlaylistStore
    @EnvironmentObject private var generatedQueueSession: GeneratedQueueSession
    @AppStorage(SettingsKeys.rediscoveryStrength) private var rediscoveryStrength = RediscoveryStrengthSetting.defaultValue
    @AppStorage(SettingsKeys.lastSelectedPlaylistID) private var lastSelectedPlaylistID = ""
    @AppStorage(SettingsKeys.playlistSongSortOption) private var songSortRawValue = PlaylistSongSortOption.defaultValue.rawValue
    @AppStorage(SettingsKeys.showPlayCounts) private var showPlayCounts = AppSettingDefaults.showPlayCounts
    @ScaledMetric(relativeTo: .title) private var heroArtworkSize = 210
    @StateObject private var viewModel: PlaylistViewModel
    @State private var listMode = ListMode.upNext
    @State private var navigationBarBottom: CGFloat = 100
    @State private var showsNavigationTitle = false
    @State private var playFeedbackTrigger = 0
    @State private var reshuffleFeedbackTrigger = 0

    /// Opens a playlist. Pass the saved queue when it belongs to this playlist
    /// so its order and live progress carry over; otherwise a fresh preview
    /// order is generated immediately.
    init(playlist: LibraryPlaylist, savedQueue: PlaylistViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: savedQueue ?? Self.previewQueue(for: playlist))
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
        .background(alignment: .top) {
            ArtworkGlowBackground(color: ArtworkPalette.averageColor(of: viewModel.playlist.artwork))
                .frame(height: 460)
                .ignoresSafeArea()
        }
        .background(Color(.systemBackground))
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
            lastSelectedPlaylistID = viewModel.playlist.persistentIDString
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

    // MARK: Header

    private var header: some View {
        VStack(spacing: 16) {
            PlaylistArtworkView(playlist: viewModel.playlist, size: min(heroArtworkSize, 280))
                .shadow(color: .black.opacity(0.22), radius: 22, y: 12)
                .padding(.top, 12)

            VStack(spacing: 6) {
                Text(viewModel.playlist.name)
                    .font(.title.bold())
                    .tracking(-0.4)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .onGeometryChange(for: Bool.self) { proxy in
                        proxy.frame(in: .global).maxY < navigationBarBottom
                    } action: { isHidden in
                        withAnimation(.strongEaseOut(duration: 0.16)) {
                            showsNavigationTitle = isHidden
                        }
                    }

                headerSubtitle
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
            }

            actionButtons
                .padding(.top, 4)

            rediscoveryMenu
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }

    private var headerSubtitle: Text {
        let songs = Text(localizedSongCount(viewModel.playlist.entries.count))
            .foregroundStyle(Color("SecondaryText"))
        guard let summary = localizedRediscoverySummary(viewModel.rediscoveryInsight) else {
            return songs
        }
        return songs
            + Text(verbatim: " · ").foregroundStyle(Color("SecondaryText"))
            + Text(summary).foregroundStyle(Color("AccentColor"))
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
            Section("Less-played songs lead the queue by") {
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
                    .foregroundStyle(Color("AccentColor"))
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
                    .foregroundStyle(Color("SecondaryText"))
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Rediscovery strength")
        .accessibilityValue(strengthName)
        .accessibilityHint("Chooses how strongly less-played songs lead the order")
    }

    private var pinButton: some View {
        let isPinned = pinnedPlaylistStore.isPinned(viewModel.playlist.persistentIDString)
        return Button {
            pinnedPlaylistStore.toggle(viewModel.playlist.persistentIDString)
        } label: {
            Label(
                isPinned ? String(localized: "Unpin Playlist") : String(localized: "Pin Playlist"),
                systemImage: isPinned ? "pin.fill" : "pin"
            )
        }
        .sensoryFeedback(.selection, trigger: isPinned)
    }

    // MARK: Song list

    private var sectionHeader: some View {
        HStack(spacing: 12) {
            Picker("Show", selection: $listMode.animation(.strongEaseOut(duration: 0.2))) {
                Text("Up Next").tag(ListMode.upNext)
                Text("All Songs").tag(ListMode.allSongs)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

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
                        freshness: viewModel.rediscoveryInsight.freshness(forPlayCount: entry.playCount),
                        showPlayCount: showPlayCounts
                    )
                    .listRowBackground(isCurrent ? Color("AccentColor").opacity(0.08) : Color.clear)
                }
            }
        case .allSongs:
            ForEach(sortedPlaylistEntries) { entry in
                TrackRow(
                    entry: entry,
                    freshness: viewModel.rediscoveryInsight.freshness(forPlayCount: entry.playCount),
                    showPlayCount: showPlayCounts
                )
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: Actions

    private func play() {
        guard viewModel.prepareVisibleOrderForPlayback() else {
            return
        }
        generatedQueueSession.markSubmittedForPlayback(viewModel)
        playbackService.setQueueAndPlay(entries: viewModel.generatedOrder, queueID: viewModel.queueID)
        playFeedbackTrigger += 1
    }

    private func reshuffle() {
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
