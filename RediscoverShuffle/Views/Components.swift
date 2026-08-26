import MediaPlayer
import SwiftUI
import UIKit

struct ArtworkView: View {
    let artwork: MPMediaItemArtwork?
    let size: CGSize

    var body: some View {
        Group {
            if let image = artwork?.image(at: size) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(.secondarySystemFill)
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: max(6, size.width * 0.12)))
        .accessibilityHidden(true)
    }
}

struct SongRow: View {
    let entry: PlaylistEntry

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(artwork: entry.artwork, size: CGSize(width: 44, height: 44))

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(entry.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            PlayCountView(playCount: entry.playCount)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title), by \(entry.artist), played \(entry.playCount) times")
    }
}

struct QueueSongRow: View {
    let entry: PlaylistEntry
    let queuePosition: Int
    let isCurrent: Bool
    let isLowestPlayCount: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                } else {
                    Text("\(queuePosition)")
                        .font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 28, alignment: .trailing)

            ArtworkView(artwork: entry.artwork, size: CGSize(width: 48, height: 48))

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(entry.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                PlayCountView(playCount: entry.playCount)
                if isLowestPlayCount {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Among the least played")
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isCurrent ? "Currently playing at" : "Queue") position \(queuePosition), \(entry.title), by \(entry.artist), played \(entry.playCount) times\(isLowestPlayCount ? ", among the least played" : "")")
    }
}

private struct PlayCountView: View {
    let playCount: Int

    var body: some View {
        VStack(spacing: 1) {
            Text("\(playCount)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
            Text("plays")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Played \(playCount) times")
    }
}

struct NowPlayingCardView: View {
    @EnvironmentObject private var playbackService: MusicPlaybackService

    var body: some View {
        HStack(spacing: 16) {
            ArtworkView(
                artwork: playbackService.nowPlaying.artwork,
                size: CGSize(width: 84, height: 84)
            )

            VStack(alignment: .leading, spacing: 5) {
                Text("NOW PLAYING")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                Text(playbackService.nowPlaying.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(playbackService.nowPlaying.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(playbackService.playbackStateDescription)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now playing, \(playbackService.nowPlaying.title), by \(playbackService.nowPlaying.artist), \(playbackService.playbackStateDescription)")
    }
}

struct CenteredActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 22)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
