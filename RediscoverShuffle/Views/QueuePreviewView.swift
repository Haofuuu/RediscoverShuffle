import SwiftUI

struct QueuePreviewView: View {
    @EnvironmentObject private var playbackService: MusicPlaybackService
    @ObservedObject var viewModel: PlaylistViewModel
    @AppStorage(SettingsKeys.rediscoveryStrength) private var rediscoveryStrength = 1.0

    private var minimumPlayCount: Int {
        viewModel.generatedOrder.map(\.playCount).min() ?? 0
    }

    private var normalizedStrength: Double {
        guard rediscoveryStrength.isFinite else {
            return 1.0
        }

        return min(
            max(rediscoveryStrength.rounded(), WeightedShuffleEngine.supportedBiasRange.lowerBound),
            WeightedShuffleEngine.supportedBiasRange.upperBound
        )
    }

    var body: some View {
        List {
            Section {
                NowPlayingCardView()
            }

            Section {
                queueActions
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }

            Section("Generated Order") {
                ForEach(Array(viewModel.generatedOrder.enumerated()), id: \.element.id) { offset, entry in
                    QueueSongRow(
                        entry: entry,
                        queuePosition: offset + 1,
                        isLowestPlayCount: entry.playCount == minimumPlayCount
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    .overlay(alignment: .bottom) {
                        if offset < viewModel.generatedOrder.count - 1 {
                            Divider()
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .navigationTitle("Rediscovered Queue")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Playback Problem", isPresented: playbackErrorIsPresented) {
            Button("Skip Item and Continue") {
                playbackService.skipUnavailableItemAndContinue()
            }
            Button("Dismiss", role: .cancel) {
                playbackService.errorMessage = nil
            }
        } message: {
            Text(playbackService.errorMessage ?? "The Music app could not play this queue.")
        }
    }

    private var queueActions: some View {
        VStack(spacing: 0) {
            Button {
                playbackService.setQueueAndPlay(entries: viewModel.generatedOrder)
            } label: {
                CenteredActionLabel(
                    title: playbackService.isPreparing ? "Preparing…" : "Play This Order",
                    systemImage: playbackService.isPreparing ? "hourglass" : "play.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(playbackService.isPreparing || viewModel.generatedOrder.isEmpty)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
                .accessibilityHidden(true)

            Button {
                viewModel.reshuffle(bias: normalizedStrength)
            } label: {
                CenteredActionLabel(title: "Reshuffle", systemImage: "shuffle")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Creates another random order without starting playback")
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var playbackErrorIsPresented: Binding<Bool> {
        Binding(
            get: { playbackService.errorMessage != nil },
            set: { if !$0 { playbackService.errorMessage = nil } }
        )
    }
}
