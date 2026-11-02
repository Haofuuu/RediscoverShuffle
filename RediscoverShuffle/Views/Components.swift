import MediaPlayer
import MusicKit
import SwiftUI
import UIKit

// MARK: - Buttons

enum ActionButtonProminence {
    case filled
    case tinted
}

/// The app's main call-to-action style. Feedback starts on touch-down and
/// stays subtle: a 0.97 scale, or an opacity change when Reduce Motion is on.
struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.screenTheme) private var theme
    var prominence: ActionButtonProminence = .filled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .tint(foreground)
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .pressFeedback(isPressed: configuration.isPressed)
    }

    private var foreground: Color {
        switch prominence {
        case .filled: theme.onAccent
        case .tinted: theme.accentText
        }
    }

    private var background: Color {
        switch prominence {
        case .filled: theme.accent
        case .tinted: theme.accent.opacity(0.16)
        }
    }
}

/// Press feedback for custom tappable surfaces such as cards and the mini player.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pressFeedback(isPressed: configuration.isPressed)
    }
}

private struct PressFeedbackModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isPressed && reduceMotion ? 0.75 : 1)
            .animation(.strongEaseOut(duration: 0.16), value: isPressed)
    }
}

extension Animation {
    /// cubic-bezier(0.23, 1, 0.32, 1): responds immediately, then settles.
    /// The built-in ease-out is too soft for deliberate UI motion.
    static func strongEaseOut(duration: TimeInterval) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }
}

extension View {
    func pressFeedback(isPressed: Bool) -> some View {
        modifier(PressFeedbackModifier(isPressed: isPressed))
    }
}

// MARK: - Transitions

extension View {
    /// Marks the view a zoom transition grows from. Zoom transitions need
    /// iOS 18; earlier versions keep the standard push or sheet.
    @ViewBuilder
    func zoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Presents this screen by zooming out of the matching `zoomSource`.
    @ViewBuilder
    func zoomTransition(from id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

struct CenteredActionLabel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let systemImage: String
    var isLoading = false

    var body: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .accessibilityHidden(true)
            } else if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 22)
        .contentShape(Rectangle())
    }
}

// MARK: - Artwork

/// Playlist cover: the one Music shows when MusicKit provides it, otherwise
/// a 2×2 mosaic when four albums are available, a single cover, or a
/// generated cover when the playlist has no artwork.
struct PlaylistArtworkView: View {
    @EnvironmentObject private var coverStore: PlaylistCoverStore
    let playlist: LibraryPlaylist
    let size: CGFloat

    var body: some View {
        Group {
            if let cover = coverStore.covers[playlist.id] {
                // The mosaic stays underneath until Music's cover has loaded.
                ZStack {
                    songCover
                    ArtworkImage(cover.artwork, width: size, height: size)
                }
            } else {
                songCover
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: artworkCornerRadius(for: size), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: artworkCornerRadius(for: size), style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private var songCover: some View {
        Group {
            if let tiles = mosaicImages {
                let tileSize = size / 2
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        tile(tiles[0], size: tileSize)
                        tile(tiles[1], size: tileSize)
                    }
                    GridRow {
                        tile(tiles[2], size: tileSize)
                        tile(tiles[3], size: tileSize)
                    }
                }
            } else if let image = singleImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                GeneratedCoverView(seed: playlist.id, size: size)
            }
        }
        .frame(width: size, height: size)
    }

    /// Four tiles only when all four draw, so a cover never shows a hole.
    private var mosaicImages: [UIImage]? {
        guard playlist.coverArtworks.count >= 4 else {
            return nil
        }
        let tileSize = CGSize(width: size / 2, height: size / 2)
        let images = playlist.coverArtworks.prefix(4).compactMap { $0.image(at: tileSize) }
        return images.count == 4 ? images : nil
    }

    private var singleImage: UIImage? {
        let side = CGSize(width: size, height: size)
        return playlist.coverArtworks.lazy.compactMap { $0.image(at: side) }.first
    }

    private func tile(_ image: UIImage, size: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipped()
    }
}

/// A stable, curated gradient for playlists without artwork, so empty covers
/// look intentional instead of all sharing one placeholder.
struct GeneratedCoverView: View {
    let seed: UInt64
    let size: CGFloat

    private static let palettes: [(PaletteColor, PaletteColor)] = [
        (PaletteColor(red: 0.86, green: 0.31, blue: 0.33), PaletteColor(red: 0.42, green: 0.10, blue: 0.20)),
        (PaletteColor(red: 0.55, green: 0.38, blue: 0.80), PaletteColor(red: 0.22, green: 0.13, blue: 0.42)),
        (PaletteColor(red: 0.30, green: 0.47, blue: 0.82), PaletteColor(red: 0.10, green: 0.18, blue: 0.40)),
        (PaletteColor(red: 0.22, green: 0.62, blue: 0.60), PaletteColor(red: 0.06, green: 0.26, blue: 0.30)),
        (PaletteColor(red: 0.90, green: 0.58, blue: 0.28), PaletteColor(red: 0.50, green: 0.20, blue: 0.12)),
        (PaletteColor(red: 0.45, green: 0.50, blue: 0.58), PaletteColor(red: 0.16, green: 0.18, blue: 0.24)),
    ]

    /// The two colours of a generated cover, so its playlist screen can wear
    /// the same palette.
    static func colors(for seed: UInt64) -> [PaletteColor] {
        let mixed = (seed ^ (seed >> 29)) &* 0x9E37_79B9_7F4A_7C15
        let palette = palettes[Int(mixed % UInt64(palettes.count))]
        return [palette.0, palette.1]
    }

    var body: some View {
        LinearGradient(
            colors: Self.colors(for: seed).map(Color.init),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "music.note")
                .font(.system(size: max(12, size * 0.34), weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
        }
    }
}

struct ArtworkView: View {
    let artwork: MPMediaItemArtwork?
    let size: CGFloat

    var body: some View {
        Group {
            if let image = artwork?.image(at: CGSize(width: size, height: size)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(.tertiarySystemFill)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.38, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: artworkCornerRadius(for: size), style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Album art reads as a square object, not an icon: small art gets
/// proportionally round corners, large art caps out at 14pt.
private func artworkCornerRadius(for size: CGFloat) -> CGFloat {
    min(max(5, size * 0.12), 14)
}

// MARK: - Rediscovery

struct FreshnessBadge: View {
    @Environment(\.screenTheme) private var theme
    let freshness: PlayFreshness

    var body: some View {
        switch freshness {
        case .unplayed:
            badge(String(localized: "Unplayed"), systemImage: "sparkle")
        case .overlooked:
            badge(String(localized: "Overlooked"), systemImage: nil)
        case .familiar:
            EmptyView()
        }
    }

    private func badge(_ title: String, systemImage: String?) -> some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(theme.accentText)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(theme.accent.opacity(0.14), in: Capsule())
        .fixedSize()
        .accessibilityHidden(true)
    }
}

/// Animated waveform for the playing song. It holds still when paused or when
/// Reduce Motion is on.
struct NowPlayingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.screenTheme) private var theme
    let isPlaying: Bool

    var body: some View {
        Image(systemName: "waveform")
            .symbolEffect(
                .variableColor.iterative,
                options: .repeating,
                isActive: isPlaying && !reduceMotion
            )
            .foregroundStyle(theme.accentText)
            .accessibilityHidden(true)
    }
}

// MARK: - Rows

struct TrackRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.screenTheme) private var theme
    let entry: PlaylistEntry
    var position: Int?
    var isCurrent = false
    var isPlaying = false
    var freshness: PlayFreshness = .familiar
    let showPlayCount: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let position {
                Group {
                    if isCurrent {
                        NowPlayingIndicator(isPlaying: isPlaying)
                    } else {
                        Text("\(position)")
                            .font(.subheadline.monospacedDigit().weight(.medium))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                .frame(minWidth: 26, alignment: .center)
            }

            if !dynamicTypeSize.isAccessibilitySize {
                ArtworkView(artwork: entry.artwork, size: 48)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? theme.accentText : Color.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                if dynamicTypeSize.isAccessibilitySize {
                    FreshnessBadge(freshness: freshness)
                }
            }

            Spacer(minLength: 4)

            if !dynamicTypeSize.isAccessibilitySize {
                FreshnessBadge(freshness: freshness)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var subtitle: String {
        // The Unplayed badge already says "0 plays".
        guard showPlayCount, freshness != .unplayed else {
            return entry.artist
        }
        return String(
            format: String(localized: "%@ · %@"),
            locale: .current,
            entry.artist,
            localizedPlayCount(entry.playCount)
        )
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let position {
            parts.append(
                isCurrent
                    ? String(localized: "Now playing")
                    : String(format: String(localized: "Number %lld"), locale: .current, Int64(position))
            )
        }
        parts.append(
            String(format: String(localized: "%@, by %@"), locale: .current, entry.title, entry.artist)
        )
        if showPlayCount, freshness != .unplayed {
            parts.append(localizedPlayCount(entry.playCount))
        }
        switch freshness {
        case .unplayed: parts.append(String(localized: "Unplayed"))
        case .overlooked: parts.append(String(localized: "Overlooked"))
        case .familiar: break
        }
        return parts.joined(separator: String(localized: ", "))
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
                    .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Localized counts

func localizedSongCount(_ count: Int) -> String {
    if count == 1 {
        return String(localized: "1 song")
    }
    return String(
        format: String(localized: "%lld songs"),
        locale: .current,
        Int64(count)
    )
}

func localizedPlayCount(_ count: Int) -> String {
    if count == 1 {
        return String(localized: "1 play")
    }
    return String(
        format: String(localized: "%lld plays"),
        locale: .current,
        Int64(count)
    )
}

func localizedRediscoverySummary(_ insight: RediscoveryInsight) -> String? {
    var parts: [String] = []
    if insight.unplayedCount > 0 {
        parts.append(
            String(format: String(localized: "%lld unplayed"), locale: .current, Int64(insight.unplayedCount))
        )
    }
    if insight.overlookedCount > 0 {
        parts.append(
            String(format: String(localized: "%lld overlooked"), locale: .current, Int64(insight.overlookedCount))
        )
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}
