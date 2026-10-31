import SwiftUI

/// Floating bar for whatever the system Music player is playing. It stays
/// above every screen so playback is always one tap away, and its glass
/// picks up a tint from the song's artwork.
struct MiniPlayerBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var playbackService: MusicPlaybackService
    let snapshot: NowPlayingSnapshot
    let open: () -> Void

    private var palette: ArtworkColorPalette {
        ArtworkPalette.palette(for: snapshot.artwork, appearance: .init(colorScheme))
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: open) {
                HStack(spacing: 12) {
                    ArtworkView(artwork: snapshot.artwork, size: 42)
                        .id(snapshot.id)
                        .transition(.opacity)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(snapshot.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                        Text(snapshot.artist)
                            .font(.footnote)
                            .foregroundStyle(Color(palette.secondaryText))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                String(format: String(localized: "%@, by %@"), locale: .current, snapshot.title, snapshot.artist)
            )
            .accessibilityHint("Shows the player and what’s up next")

            Button(action: playbackService.togglePlayPause) {
                Image(systemName: playbackService.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(playbackService.isPlaying ? String(localized: "Pause") : String(localized: "Play"))

            Button(action: playbackService.skipToNextItem) {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Next Song")
        }
        .buttonStyle(PressableButtonStyle())
        .foregroundStyle(Color.primary)
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .floatingBarBackground(tint: Color(palette.field[0]))
        .animation(.easeInOut(duration: 0.3), value: snapshot.id)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}

private struct FloatingBarBackground: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint.opacity(0.45)), in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .background(tint.opacity(0.5), in: shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        }
    }
}

private extension View {
    func floatingBarBackground(tint: Color) -> some View {
        modifier(FloatingBarBackground(tint: tint))
    }
}

/// Full player. The room takes on the song's colours and drifts while the
/// music plays; it is always dark, like a stage, so artwork of any colour
/// reads the same way.
struct NowPlayingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var playbackService: MusicPlaybackService
    @EnvironmentObject private var generatedQueueSession: GeneratedQueueSession
    @AppStorage(SettingsKeys.showPlayCounts) private var showPlayCounts = AppSettingDefaults.showPlayCounts
    /// Artwork fills the column, so it is sized from the width rather than
    /// Dynamic Type and never overflows a small phone.
    @State private var contentWidth: CGFloat = 320

    private var liveQueue: PlaylistViewModel? {
        guard let viewModel = generatedQueueSession.lastQueueViewModel,
              playbackService.generatedQueueProgress?.queueID == viewModel.queueID else {
            return nil
        }
        return viewModel
    }

    private var palette: ArtworkColorPalette {
        ArtworkPalette.palette(for: playbackService.nowPlaying?.artwork, appearance: .dark)
    }

    /// Each song deals the field differently, so a track change is felt
    /// even when two covers share a colour.
    private var fieldArrangement: Int {
        Int(truncatingIfNeeded: playbackService.nowPlaying?.id ?? 0)
    }

    var body: some View {
        NavigationStack {
            List {
                if let snapshot = playbackService.nowPlaying {
                    playerHeader(snapshot)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                if let liveQueue {
                    upNextSection(liveQueue)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background {
                ColorField(
                    palette: palette,
                    arrangement: fieldArrangement,
                    isPlaying: playbackService.isPlaying
                )
                .ignoresSafeArea()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if let url = URL(string: "music://") {
                            openURL(url)
                        }
                    } label: {
                        Label("Open Music", systemImage: "arrow.up.forward.app")
                    }
                }
            }
        }
        .screenTheme(palette)
        .preferredColorScheme(.dark)
        .presentationBackground(Color(palette.ground))
        .presentationDragIndicator(.visible)
        .onChange(of: playbackService.nowPlaying == nil) { _, hasNothingPlaying in
            if hasNothingPlaying {
                dismiss()
            }
        }
    }

    private func playerHeader(_ snapshot: NowPlayingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ArtworkView(artwork: snapshot.artwork, size: min(contentWidth, 360))
                .shadow(color: .black.opacity(playbackService.isPlaying ? 0.45 : 0.25), radius: 30, y: 18)
                .scaleEffect(playbackService.isPlaying || reduceMotion ? 1 : 0.86)
                .animation(.smooth(duration: 0.45), value: playbackService.isPlaying)
                .id(snapshot.id)
                .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.title)
                    .font(.title2.bold())
                    .tracking(-0.3)
                    .accessibilityAddTraits(.isHeader)
                Text(snapshot.artist)
                    .font(.title3)
                    .foregroundStyle(Color(palette.secondaryText))
            }
            .id(snapshot.id)
            .transition(.opacity)
            .padding(.top, 32)

            if snapshot.duration > 0 {
                PlaybackScrubber(duration: snapshot.duration)
                    .padding(.top, 22)
            }

            HStack {
                transportButton(
                    systemImage: "backward.fill",
                    size: 30,
                    label: String(localized: "Previous Song"),
                    action: playbackService.skipToPreviousItem
                )
                Spacer()
                transportButton(
                    systemImage: playbackService.isPlaying ? "pause.fill" : "play.fill",
                    size: 50,
                    label: playbackService.isPlaying ? String(localized: "Pause") : String(localized: "Play"),
                    action: playbackService.togglePlayPause
                )
                Spacer()
                transportButton(
                    systemImage: "forward.fill",
                    size: 30,
                    label: String(localized: "Next Song"),
                    action: playbackService.skipToNextItem
                )
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 28)
            .padding(.top, 12)
        }
        .animation(.smooth(duration: 0.5), value: snapshot.id)
        .padding(.horizontal, 28)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width - 56
        } action: { width in
            contentWidth = max(width, 120)
        }
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
    }

    private func transportButton(
        systemImage: String,
        size: CGFloat,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 76, height: 76)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
    }

    private func upNextSection(_ viewModel: PlaylistViewModel) -> some View {
        let isCurrentVisible = playbackService.generatedQueueProgress?.isCurrentEntryVisible == true
        let upcoming = Array(viewModel.visibleGeneratedOrder.dropFirst(isCurrentVisible ? 1 : 0))

        return Section {
            if upcoming.isEmpty {
                Text("This is the last song in the queue.")
                    .font(.subheadline)
                    .foregroundStyle(Color(palette.secondaryText))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { offset, entry in
                    TrackRow(
                        entry: entry,
                        position: offset + 1,
                        freshness: viewModel.rediscoveryInsight.freshness(forPlayCount: entry.playCount),
                        showPlayCount: showPlayCounts
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Color.primary.opacity(0.12))
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Up Next")
                    .font(.title3.bold())
                    .foregroundStyle(Color.primary)
                Text(
                    String(format: String(localized: "From %@"), locale: .current, viewModel.playlist.name)
                )
                .font(.subheadline)
                .foregroundStyle(Color(palette.secondaryText))
            }
            .textCase(nil)
            .padding(.vertical, 4)
        }
    }
}

/// Elapsed and remaining time, with drag-to-seek. Music posts nothing as
/// time passes, so the bar reads the player twice a second while visible.
private struct PlaybackScrubber: View {
    @EnvironmentObject private var playbackService: MusicPlaybackService
    @Environment(\.screenTheme) private var theme
    let duration: TimeInterval
    @State private var scrubFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let elapsed = scrubFraction.map { $0 * duration } ?? min(playbackService.currentPlaybackTime, duration)
            let fraction = min(max(elapsed / duration, 0), 1)

            VStack(spacing: 8) {
                GeometryReader { proxy in
                    let isScrubbing = scrubFraction != nil
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.2))
                        Capsule()
                            .fill(Color.primary.opacity(isScrubbing ? 1 : 0.85))
                            .frame(width: proxy.size.width * fraction)
                            .animation(isScrubbing ? nil : .linear(duration: 0.5), value: fraction)
                    }
                    .frame(height: isScrubbing ? 10 : 6)
                    .frame(maxHeight: .infinity)
                    .animation(.strongEaseOut(duration: 0.2), value: isScrubbing)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                scrubFraction = min(max(value.location.x / proxy.size.width, 0), 1)
                            }
                            .onEnded { _ in
                                if let scrubFraction {
                                    playbackService.seek(to: scrubFraction * duration)
                                }
                                scrubFraction = nil
                            }
                    )
                }
                .frame(height: 28)

                HStack {
                    Text(Self.format(elapsed))
                    Spacer()
                    Text(verbatim: "−" + Self.format(duration - elapsed))
                }
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(theme.secondaryText)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Playback Position")
            .accessibilityValue(
                String(
                    format: String(localized: "%@ of %@"),
                    locale: .current,
                    Self.format(elapsed),
                    Self.format(duration)
                )
            )
            .accessibilityAdjustableAction { direction in
                let step: TimeInterval = direction == .increment ? 15 : -15
                playbackService.seek(to: min(max(elapsed + step, 0), duration))
            }
        }
        .sensoryFeedback(.selection, trigger: scrubFraction == nil)
    }

    private static func format(_ time: TimeInterval) -> String {
        Duration.seconds(max(0, time).rounded(.down)).formatted(.time(pattern: .minuteSecond))
    }
}
