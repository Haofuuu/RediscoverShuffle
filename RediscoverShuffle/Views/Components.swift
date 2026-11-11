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
        case .tinted: .primary
        }
    }

    /// The second button is neutral rather than a pale wash of the ember, so
    /// the ember appears at full strength or not at all.
    private var background: Color {
        switch prominence {
        case .filled: theme.accent
        case .tinted: .primary.opacity(0.08)
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

    /// A pane of glass on iOS 26 and later, so the page's colours show
    /// through; a material with a hairline edge before that.
    @ViewBuilder
    func glassPane(in shape: some InsettableShape) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5) }
        }
    }
}

// MARK: - Segmented switcher

/// A segmented control drawn in SwiftUI, used on iOS 26 and later. There the
/// system's segmented control draws its selected label through Liquid Glass,
/// and while a swipe back shrinks the page to follow the finger, the glass
/// applied the shrink a second time, so the selected label showed up twice.
/// This one keeps a Liquid Glass thumb but draws the labels above it, never
/// through it, so they shrink with the page like everything else.
///
/// Tap a segment or drag the thumb across, as with the system control; the
/// thumb lifts a little while a finger is on it, and the change animates
/// with the binding's animation. On a playlist page it tells the page where
/// it sits, so a drag on it never turns into a swipe back, and VoiceOver
/// sees a standard segmented picker.
@available(iOS 26.0, *)
struct SegmentedSwitcher<Value: Hashable>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.playlistPage) private var page
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [(value: Value, label: Text)]
    /// The segment under the finger while it is down.
    @State private var trackedValue: Value?
    @State private var width: CGFloat = 0
    @Namespace private var thumbSpace

    private static var inset: CGFloat { 2 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isShown = option.value == (trackedValue ?? selection)
                option.label
                    .font(.subheadline.weight(isShown ? .semibold : .medium))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background {
                        if isShown {
                            thumb
                                .matchedGeometryEffect(id: "thumb", in: thumbSpace)
                        }
                    }
            }
        }
        .padding(Self.inset)
        .background(Color.primary.opacity(0.08), in: Capsule())
        .contentShape(Capsule())
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .playlistPage)
        } action: { frame in
            page?.sidewaysDragFrame = frame
        }
        .onDisappear {
            page?.sidewaysDragFrame = .null
        }
        .gesture(drag)
        .accessibilityRepresentation {
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { index in
                    options[index].label.tag(options[index].value)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    /// Liquid Glass, tinted white on the light page so it stands clear of
    /// the track, and lifted while a finger is on the switcher.
    private var thumb: some View {
        let glass: Glass = colorScheme == .dark ? .regular : .regular.tint(Color.white.opacity(0.6))
        return Color.clear
            .glassEffect(glass.interactive(), in: Capsule())
            .scaleEffect(trackedValue != nil && !reduceMotion ? 1.06 : 1)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let segment = option(at: value.location.x)
                guard segment != trackedValue else {
                    return
                }
                withAnimation(reduceMotion ? nil : .strongEaseOut(duration: 0.2)) {
                    trackedValue = segment
                }
            }
            .onEnded { value in
                let chosen = option(at: value.location.x)
                // A drag that went up or down was meant for the list, so it
                // leaves the switcher as it was.
                let isVertical = abs(value.translation.height) > max(20, abs(value.translation.width))
                withAnimation(reduceMotion ? nil : .strongEaseOut(duration: 0.2)) {
                    trackedValue = nil
                }
                if !isVertical, chosen != selection {
                    selection = chosen
                }
            }
    }

    private func option(at x: CGFloat) -> Value {
        let segmentWidth = (width - Self.inset * 2) / CGFloat(max(options.count, 1))
        guard segmentWidth > 0, !options.isEmpty else {
            return selection
        }
        let index = Int(((x - Self.inset) / segmentWidth).rounded(.down))
        return options[min(max(index, 0), options.count - 1)].value
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
        let images = playlist.coverArtworks.prefix(4).compactMap {
            ArtworkImageCache.image(for: $0, side: size / 2)
        }
        return images.count == 4 ? images : nil
    }

    private var singleImage: UIImage? {
        playlist.coverArtworks.lazy.compactMap { ArtworkImageCache.image(for: $0, side: size) }.first
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
            if let artwork, let image = ArtworkImageCache.image(for: artwork, side: size) {
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

/// Decoded artwork, kept so lists don't decode the same covers again on every
/// redraw, such as each frame of a scroll or a playback update.
@MainActor
enum ArtworkImageCache {
    private final class Sizes {
        var images: [Int: UIImage] = [:]
        var missing: Set<Int> = []
    }

    private static let cache: NSCache<MPMediaItemArtwork, Sizes> = {
        let cache = NSCache<MPMediaItemArtwork, Sizes>()
        cache.countLimit = 500
        return cache
    }()

    static func image(for artwork: MPMediaItemArtwork, side: CGFloat) -> UIImage? {
        let key = Int(side.rounded(.up))
        let sizes: Sizes
        if let cached = cache.object(forKey: artwork) {
            sizes = cached
        } else {
            sizes = Sizes()
            cache.setObject(sizes, forKey: artwork)
        }
        if let image = sizes.images[key] {
            return image
        }
        guard !sizes.missing.contains(key) else {
            return nil
        }
        let image = artwork.image(at: CGSize(width: side, height: side))
        if let image {
            sizes.images[key] = image
        } else {
            sizes.missing.insert(key)
        }
        return image
    }
}

/// Album art reads as a square object, not an icon: small art gets
/// proportionally round corners, large art caps out at 14pt.
func artworkCornerRadius(for size: CGFloat) -> CGFloat {
    min(max(5, size * 0.12), 14)
}

// MARK: - Rediscovery

extension PlayFreshness {
    /// The name every screen gives this kind of song; familiar songs have none.
    var title: String? {
        switch self {
        case .unplayed: String(localized: "Unplayed")
        case .overlooked: String(localized: "Overlooked")
        case .familiar: nil
        }
    }

    /// Unplayed songs carry the sparkle wherever they are counted.
    var systemImage: String? {
        self == .unplayed ? "sparkle" : nil
    }
}

struct FreshnessBadge: View {
    @Environment(\.screenTheme) private var theme
    let freshness: PlayFreshness

    var body: some View {
        if let title = freshness.title {
            badge(title, systemImage: freshness.systemImage)
        }
    }

    private func badge(_ title: String, systemImage: String?) -> some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
                    .foregroundStyle(theme.accent)
            }
            Text(title)
                .foregroundStyle(.primary)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.primary.opacity(0.08), in: Capsule())
        .fixedSize()
        .accessibilityHidden(true)
    }
}

/// Animated waveform for the playing song. It holds still when paused or when
/// Reduce Motion is on. It is drawn in the text colour, at a size that reads
/// as clearly as the row number it replaces; the ember was too faint on the
/// deep artwork colours it often sits on.
struct NowPlayingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isPlaying: Bool

    var body: some View {
        Image(systemName: "waveform")
            .imageScale(.large)
            .fontWeight(.semibold)
            .symbolEffect(
                .variableColor.iterative,
                options: .repeating,
                isActive: isPlaying && !reduceMotion
            )
            .foregroundStyle(.primary)
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
                    .foregroundStyle(Color.primary)
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
        if let title = freshness.title {
            parts.append(title)
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

func localizedUnplayedCount(_ count: Int) -> String {
    String(format: String(localized: "%lld unplayed"), locale: .current, Int64(count))
}

func localizedOverlookedCount(_ count: Int) -> String {
    String(format: String(localized: "%lld overlooked"), locale: .current, Int64(count))
}

func localizedRediscoverySummary(_ insight: RediscoveryInsight) -> String? {
    var parts: [String] = []
    if insight.unplayedCount > 0 {
        parts.append(localizedUnplayedCount(insight.unplayedCount))
    }
    if insight.overlookedCount > 0 {
        parts.append(localizedOverlookedCount(insight.overlookedCount))
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}
