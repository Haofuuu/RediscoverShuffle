import SwiftUI

struct QueuePreviewView: View {
    @EnvironmentObject private var playbackService: MusicPlaybackService
    @EnvironmentObject private var generatedQueueSession: GeneratedQueueSession
    @ObservedObject var viewModel: PlaylistViewModel
    @AppStorage(SettingsKeys.rediscoveryStrength) private var rediscoveryStrength = 1.0

    private var minimumPlayCount: Int {
        viewModel.visibleGeneratedOrder.map(\.playCount).min() ?? 0
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

            Section {
                if viewModel.visibleGeneratedOrder.isEmpty {
                    ContentUnavailableView(
                        "Queue Complete",
                        systemImage: "checkmark.circle",
                        description: Text("Every available item in this generated order has been reached.")
                    )
                } else {
                    ForEach(Array(viewModel.visibleGeneratedOrder.enumerated()), id: \.element.id) { offset, entry in
                        QueueSongRow(
                            entry: entry,
                            queuePosition: offset + 1,
                            isCurrent: liveProgress?.isCurrentEntryVisible == true && offset == 0,
                            isLowestPlayCount: entry.playCount == minimumPlayCount
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                        .overlay(alignment: .bottom) {
                            if offset < viewModel.visibleGeneratedOrder.count - 1 {
                                Divider()
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            } header: {
                Text(queueSectionTitle)
            } footer: {
                if viewModel.playbackPosition != nil {
                    Text("Earlier songs move out of this list as Music advances. When this queue is active, going back brings them into the list again.")
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
                playbackService.dismissPlaybackError()
            }
        } message: {
            Text(playbackService.errorMessage ?? "The Music app could not play this queue.")
        }
    }

    private var queueActions: some View {
        VStack(spacing: 0) {
            Button {
                guard viewModel.prepareVisibleOrderForPlayback() else {
                    return
                }
                generatedQueueSession.markSubmittedForPlayback(viewModel)
                playbackService.setQueueAndPlay(
                    entries: viewModel.generatedOrder,
                    queueID: viewModel.queueID
                )
            } label: {
                CenteredActionLabel(
                    title: playbackService.isPreparing ? "Preparing…" : "Play This Order",
                    systemImage: playbackService.isPreparing ? "hourglass" : "play.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(playbackService.isPreparing || viewModel.visibleGeneratedOrder.isEmpty)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
                .accessibilityHidden(true)

            Button {
                viewModel.reshuffle(bias: normalizedStrength)
                generatedQueueSession.remember(viewModel)
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

    private var queueSectionTitle: String {
        if isFollowingLiveQueue {
            return liveProgress?.isCurrentEntryVisible == true
                ? "Current and Upcoming"
                : "Upcoming"
        }
        if viewModel.playbackPosition != nil {
            return "Remaining Order"
        }
        return "Generated Order"
    }
}
