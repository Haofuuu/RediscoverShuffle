import Combine

/// Keeps the most recently generated queue alive while the app is running.
/// MediaPlayer objects are intentionally not serialized to disk.
@MainActor
final class GeneratedQueueSession: ObservableObject {
    @Published private(set) var lastQueueViewModel: PlaylistViewModel?

    func remember(_ viewModel: PlaylistViewModel) {
        guard !viewModel.generatedOrder.isEmpty else {
            return
        }

        lastQueueViewModel = viewModel
    }
}
