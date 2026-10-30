import CoreImage
import CoreImage.CIFilterBuiltins
import MediaPlayer
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
        case .filled: Color("AccentForeground")
        case .tinted: Color("AccentColor")
        }
    }

    private var background: Color {
        switch prominence {
        case .filled: Color("AccentColor")
        case .tinted: Color("AccentColor").opacity(0.13)
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

/// Playlist cover: a 2×2 mosaic when four albums are available, a single
/// cover otherwise, and a generated cover when the playlist has no artwork.
struct PlaylistArtworkView: View {
    let playlist: LibraryPlaylist
    let size: CGFloat

    var body: some View {
        Group {
            if playlist.coverArtworks.count >= 4 {
                let tileSize = size / 2
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        tile(playlist.coverArtworks[0], size: tileSize)
                        tile(playlist.coverArtworks[1], size: tileSize)
                    }
                    GridRow {
                        tile(playlist.coverArtworks[2], size: tileSize)
                        tile(playlist.coverArtworks[3], size: tileSize)
                    }
                }
            } else if let artwork = playlist.artwork,
                      let image = artwork.image(at: CGSize(width: size, height: size)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                GeneratedCoverView(seed: playlist.id, size: size)
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

    @ViewBuilder
    private func tile(_ artwork: MPMediaItemArtwork, size: CGFloat) -> some View {
        if let image = artwork.image(at: CGSize(width: size, height: size)) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipped()
        } else {
            Color(.tertiarySystemFill)
                .frame(width: size, height: size)
        }
    }
}

/// A stable, curated gradient for playlists without artwork, so empty covers
/// look intentional instead of all sharing one placeholder.
struct GeneratedCoverView: View {
    let seed: UInt64
    let size: CGFloat

    private static let palettes: [(Color, Color)] = [
        (Color(red: 0.86, green: 0.31, blue: 0.33), Color(red: 0.42, green: 0.10, blue: 0.20)),
        (Color(red: 0.55, green: 0.38, blue: 0.80), Color(red: 0.22, green: 0.13, blue: 0.42)),
        (Color(red: 0.30, green: 0.47, blue: 0.82), Color(red: 0.10, green: 0.18, blue: 0.40)),
        (Color(red: 0.22, green: 0.62, blue: 0.60), Color(red: 0.06, green: 0.26, blue: 0.30)),
        (Color(red: 0.90, green: 0.58, blue: 0.28), Color(red: 0.50, green: 0.20, blue: 0.12)),
        (Color(red: 0.45, green: 0.50, blue: 0.58), Color(red: 0.16, green: 0.18, blue: 0.24)),
    ]

    var body: some View {
        let mixed = (seed ^ (seed >> 29)) &* 0x9E37_79B9_7F4A_7C15
        let palette = Self.palettes[Int(mixed % UInt64(Self.palettes.count))]
        LinearGradient(
            colors: [palette.0, palette.1],
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

/// Average colour of a piece of artwork, used to tint headers. Results are
/// cached per artwork object because Core Image work is not free.
@MainActor
enum ArtworkPalette {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])
    private static let cache = NSCache<MPMediaItemArtwork, UIColor>()

    static func averageColor(of artwork: MPMediaItemArtwork?) -> Color? {
        guard let artwork else {
            return nil
        }
        if let cached = cache.object(forKey: artwork) {
            return Color(uiColor: cached)
        }
        guard let image = artwork.image(at: CGSize(width: 48, height: 48)),
              let input = CIImage(image: image) else {
            return nil
        }

        let filter = CIFilter.areaAverage()
        filter.inputImage = input
        filter.extent = input.extent
        guard let output = filter.outputImage else {
            return nil
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        let color = UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
        cache.setObject(color, forKey: artwork)
        return Color(uiColor: color)
    }
}

/// Soft wash of the artwork's colour behind a header, fading into the page.
struct ArtworkGlowBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let color: Color?

    var body: some View {
        LinearGradient(
            colors: [
                (color ?? Color("AccentColor")).opacity(colorScheme == .dark ? 0.45 : 0.3),
                Color(.systemBackground).opacity(0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Rediscovery

struct FreshnessBadge: View {
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
        .foregroundStyle(Color("AccentColor"))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color("AccentColor").opacity(0.12), in: Capsule())
        .fixedSize()
        .accessibilityHidden(true)
    }
}

/// Animated waveform for the playing song. It holds still when paused or when
/// Reduce Motion is on.
struct NowPlayingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isPlaying: Bool

    var body: some View {
        Image(systemName: "waveform")
            .symbolEffect(
                .variableColor.iterative,
                options: .repeating,
                isActive: isPlaying && !reduceMotion
            )
            .foregroundStyle(Color("AccentColor"))
            .accessibilityHidden(true)
    }
}

// MARK: - Rows

struct TrackRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                            .foregroundStyle(Color("SecondaryText"))
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
                    .foregroundStyle(isCurrent ? Color("AccentColor") : Color.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color("SecondaryText"))
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
