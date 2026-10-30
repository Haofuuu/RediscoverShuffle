import SwiftUI

/// Floating bar for whatever the system Music player is playing. It stays
/// above every screen so playback is always one tap away.
struct MiniPlayerBar: View {
    @EnvironmentObject private var playbackService: MusicPlaybackService
    let snapshot: NowPlayingSnapshot
    let open: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: open) {
                HStack(spacing: 12) {
                    ArtworkView(artwork: snapshot.artwork, size: 42)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(snapshot.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                        Text(snapshot.artist)
                            .font(.footnote)
                            .foregroundStyle(Color("SecondaryText"))
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
        .floatingBarBackground()
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}

private struct FloatingBarBackground: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        }
    }
}

private extension View {
    func floatingBarBackground() -> some View {
        modifier(FloatingBarBackground())
    }
}

/// Full player: large artwork, transport controls, and the rest of the
/// Rediscover queue when Music is playing one.
struct NowPlayingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var playbackService: MusicPlaybackService
    @EnvironmentObject private var generatedQueueSession: GeneratedQueueSession
    @AppStorage(SettingsKeys.showPlayCounts) private var showPlayCounts = AppSettingDefaults.showPlayCounts
    @ScaledMetric(relativeTo: .largeTitle) private var artworkSize = 270

    private var liveQueue: PlaylistViewModel? {
        guard let viewModel = generatedQueueSession.lastQueueViewModel,
              playbackService.generatedQueueProgress?.queueID == viewModel.queueID else {
            return nil
        }
        return viewModel
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
            .background(alignment: .top) {
                ArtworkGlowBackground(color: ArtworkPalette.averageColor(of: playbackService.nowPlaying?.artwork))
                    .frame(height: 560)
                    .ignoresSafeArea()
            }
            .background(Color(.systemBackground))
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
        .presentationDragIndicator(.visible)
        .onChange(of: playbackService.nowPlaying == nil) { _, hasNothingPlaying in
            if hasNothingPlaying {
                dismiss()
            }
        }
    }

    private func playerHeader(_ snapshot: NowPlayingSnapshot) -> some View {
        VStack(spacing: 22) {
            ArtworkView(artwork: snapshot.artwork, size: min(artworkSize, 320))
                .shadow(color: .black.opacity(playbackService.isPlaying ? 0.28 : 0.14), radius: 24, y: 14)
                .scaleEffect(playbackService.isPlaying || reduceMotion ? 1 : 0.86)
                .animation(.smooth(duration: 0.4), value: playbackService.isPlaying)
                .padding(.top, 8)

            VStack(spacing: 4) {
                Text(snapshot.title)
                    .font(.title2.bold())
                    .tracking(-0.3)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(snapshot.artist)
                    .font(.title3)
                    .foregroundStyle(Color("SecondaryText"))
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 36) {
                transportButton(
                    systemImage: "backward.fill",
                    size: 28,
                    label: String(localized: "Previous Song"),
                    action: playbackService.skipToPreviousItem
                )
                transportButton(
                    systemImage: playbackService.isPlaying ? "pause.fill" : "play.fill",
                    size: 46,
                    label: playbackService.isPlaying ? String(localized: "Pause") : String(localized: "Play"),
                    action: playbackService.togglePlayPause
                )
                transportButton(
                    systemImage: "forward.fill",
                    size: 28,
                    label: String(localized: "Next Song"),
                    action: playbackService.skipToNextItem
                )
            }
            .foregroundStyle(Color.primary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
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
                .frame(width: 72, height: 72)
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
                    .foregroundStyle(Color("SecondaryText"))
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
                .foregroundStyle(Color("SecondaryText"))
            }
            .textCase(nil)
            .padding(.vertical, 4)
        }
    }
}
