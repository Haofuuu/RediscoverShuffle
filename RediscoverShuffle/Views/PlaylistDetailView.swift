import SwiftUI

struct PlaylistDetailView: View {
    @EnvironmentObject private var playbackService: MusicPlaybackService
    @EnvironmentObject private var pinnedPlaylistStore: PinnedPlaylistStore
    @EnvironmentObject private var generatedQueueSession: GeneratedQueueSession
    @AppStorage(SettingsKeys.rediscoveryStrength) private var rediscoveryStrength = 1.0
    @AppStorage(SettingsKeys.lastSelectedPlaylistID) private var lastSelectedPlaylistID = ""
    @StateObject private var viewModel: PlaylistViewModel
    @State private var showsQueue = false
    @State private var presentedQueueViewModel: PlaylistViewModel?

    init(playlist: LibraryPlaylist) {
        _viewModel = StateObject(wrappedValue: PlaylistViewModel(playlist: playlist))
    }

    var body: some View {
        List {
            Section {
                strengthControl

                Button {
                    viewModel.reshuffle(bias: normalizedStrength)
                    generatedQueueSession.remember(viewModel)
                    presentedQueueViewModel = viewModel
                    playbackService.setQueueAndPlay(entries: viewModel.generatedOrder)
                    showsQueue = true
                } label: {
                    CenteredActionLabel(title: "Shuffle and Play", systemImage: "shuffle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.playlist.entries.isEmpty)
                .accessibilityHint("Creates a new weighted order and starts it in the Music app")
            }

            if let lastQueueViewModel = generatedQueueSession.lastQueueViewModel {
                Section {
                    lastQueueButton(for: lastQueueViewModel)
                }
            }

            Section("Songs in Playlist") {
                if viewModel.playlist.entries.isEmpty {
                    ContentUnavailableView(
                        "Empty Playlist",
                        systemImage: "music.note",
                        description: Text("This playlist has no songs to shuffle.")
                    )
                } else {
                    ForEach(viewModel.playlist.entries) { entry in
                        SongRow(entry: entry)
                    }
                }
            }
        }
        .navigationTitle(viewModel.playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    pinnedPlaylistStore.toggle(viewModel.playlist.persistentIDString)
                } label: {
                    Label(
                        pinnedPlaylistStore.isPinned(viewModel.playlist.persistentIDString)
                            ? "Unpin Playlist"
                            : "Pin Playlist",
                        systemImage: pinnedPlaylistStore.isPinned(viewModel.playlist.persistentIDString)
                            ? "pin.slash.fill"
                            : "pin.fill"
                    )
                }
            }
        }
        .onAppear {
            lastSelectedPlaylistID = viewModel.playlist.persistentIDString
            rediscoveryStrength = normalizedStrength
        }
        .navigationDestination(isPresented: $showsQueue) {
            if let presentedQueueViewModel {
                QueuePreviewView(viewModel: presentedQueueViewModel)
            }
        }
    }

    private func lastQueueButton(for lastQueueViewModel: PlaylistViewModel) -> some View {
        let songCount = lastQueueViewModel.generatedOrder.count

        return Button {
            presentedQueueViewModel = lastQueueViewModel
            showsQueue = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.number")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 30)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("View Last Queue")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("\(lastQueueViewModel.playlist.name) · \(songCount) \(songCount == 1 ? "song" : "songs")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View last generated queue for \(lastQueueViewModel.playlist.name), \(songCount) songs")
        .accessibilityHint("Opens the previously generated Rediscovered Queue without changing its order")
    }

    private var strengthControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Rediscovery Strength")
                    .font(.headline)
                Spacer()
                Text("\(Int(normalizedStrength)) · \(strengthName)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
            }

            Slider(
                value: strengthBinding,
                in: WeightedShuffleEngine.supportedBiasRange,
                step: 1.0
            ) {
                Text("Rediscovery Strength")
            } minimumValueLabel: {
                Text("0")
                    .accessibilityHidden(true)
            } maximumValueLabel: {
                Text("5")
                    .accessibilityHidden(true)
            }
            .accessibilityValue("\(strengthName), \(Int(normalizedStrength)) out of 5")

            Text("Songs you have played less often are more likely to appear earlier, but every shuffle remains random.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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

    private var strengthBinding: Binding<Double> {
        Binding(
            get: { normalizedStrength },
            set: { rediscoveryStrength = min(max($0.rounded(), 0.0), 5.0) }
        )
    }

    private var strengthName: String {
        switch Int(normalizedStrength) {
        case 0: return "Normal"
        case 1: return "Gentle"
        case 2: return "Moderate"
        case 3: return "Strong"
        case 4: return "Very Strong"
        default: return "Maximum"
        }
    }
}
