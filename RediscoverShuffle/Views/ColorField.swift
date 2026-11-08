import MediaPlayer
import MusicKit
import SwiftUI
import UIKit

// MARK: - Palettes from artwork

extension Color {
    init(_ color: PaletteColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue)
    }

    /// The app icon's ember. It is the one accent in the app, the same in
    /// light and dark mode, so it is used for fills and symbols; text in it
    /// would fall below 4.5:1 on dark surfaces.
    static let ember = Color("AccentColor")
}

extension PaletteColor {
    init?(_ color: CGColor) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: space, intent: .defaultIntent, options: nil),
              let components = converted.components,
              components.count >= 3 else {
            return nil
        }
        self.init(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
    }
}

extension ArtworkColorPalette.Appearance {
    init(_ colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .dark : .light
    }
}

/// Reads colours out of artwork and turns them into screen palettes. Both
/// steps are cached because palettes are asked for on every redraw.
@MainActor
enum ArtworkPalette {
    /// The app icon's ember, used when artwork has no colour to offer.
    static let ember = PaletteColor(red: 0.784, green: 0.196, blue: 0.247)

    private final class SwatchList {
        let colors: [PaletteColor]

        init(_ colors: [PaletteColor]) {
            self.colors = colors
        }
    }

    private struct PaletteKey: Hashable {
        let swatches: [PaletteColor]
        let appearance: ArtworkColorPalette.Appearance
    }

    private static let swatchCache = NSCache<MPMediaItemArtwork, SwatchList>()
    private static var paletteCache: [PaletteKey: ArtworkColorPalette] = [:]
    private static var songSwatches: [MPMediaEntityPersistentID: [PaletteColor]] = [:]

    /// The app icon's world: ember glowing out of near-black, with a deep
    /// wine between them. Used where there is no artwork yet, such as
    /// onboarding.
    static func brand(appearance: ArtworkColorPalette.Appearance) -> ArtworkColorPalette {
        palette(
            swatches: [
                ember,
                PaletteColor(red: 0.12, green: 0.1, blue: 0.12),
                PaletteColor(red: 0.45, green: 0.08, blue: 0.16),
            ],
            appearance: appearance
        )
    }

    /// Pass the swatches of Music's own cover when there is one, so the field
    /// matches the cover on screen rather than the songs behind it.
    static func palette(
        for playlist: LibraryPlaylist,
        coverSwatches: [PaletteColor]?,
        appearance: ArtworkColorPalette.Appearance
    ) -> ArtworkColorPalette {
        let swatches = coverSwatches.flatMap { $0.isEmpty ? nil : $0 } ?? swatches(for: playlist)
        return palette(swatches: swatches, appearance: appearance)
    }

    /// The quiet room shown when nothing is playing.
    static func fallback(appearance: ArtworkColorPalette.Appearance) -> ArtworkColorPalette {
        palette(swatches: [], appearance: appearance)
    }

    /// A song keeps the same colours every time its player opens. iOS hands
    /// out a fresh artwork object for each playback update, sometimes a flat
    /// stand-in while the real cover loads, so the colours are remembered
    /// per song; flat greys give way only once the real cover shows colour.
    static func palette(
        forSong id: MPMediaEntityPersistentID,
        artwork: MPMediaItemArtwork?,
        appearance: ArtworkColorPalette.Appearance
    ) -> ArtworkColorPalette {
        palette(swatches: swatches(forSong: id, artwork: artwork), appearance: appearance)
    }

    private static func swatches(
        forSong id: MPMediaEntityPersistentID,
        artwork: MPMediaItemArtwork?
    ) -> [PaletteColor] {
        let known = songSwatches[id]
        if let known, known.contains(where: { !$0.isNeutral }) {
            return known
        }
        let fresh = artwork.map(swatches(of:)) ?? []
        guard !fresh.isEmpty else {
            return known ?? []
        }
        if let known, fresh.allSatisfy(\.isNeutral) {
            return known
        }
        if songSwatches.count >= 200 {
            songSwatches.removeAll()
        }
        songSwatches[id] = fresh
        return fresh
    }

    private static func palette(
        swatches: [PaletteColor],
        appearance: ArtworkColorPalette.Appearance
    ) -> ArtworkColorPalette {
        let key = PaletteKey(swatches: swatches, appearance: appearance)
        if let cached = paletteCache[key] {
            return cached
        }
        if paletteCache.count >= 64 {
            paletteCache.removeAll()
        }
        let palette = ArtworkColorPalette(
            swatches: swatches,
            fallback: ember,
            appearance: appearance
        )
        paletteCache[key] = palette
        return palette
    }

    /// Each cover's leading colour comes first, so a mosaic's field shows
    /// every album in it rather than three shades of the first one.
    private static func swatches(for playlist: LibraryPlaylist) -> [PaletteColor] {
        guard !playlist.coverArtworks.isEmpty else {
            return GeneratedCoverView.colors(for: playlist.id)
        }
        let perCover = playlist.coverArtworks.prefix(4).map(swatches(of:))
        var combined: [PaletteColor] = []
        for rank in 0..<3 {
            for colors in perCover where colors.indices.contains(rank) {
                combined.append(colors[rank])
            }
        }
        return Array(combined.prefix(4))
    }

    private static func swatches(of artwork: MPMediaItemArtwork) -> [PaletteColor] {
        if let cached = swatchCache.object(forKey: artwork) {
            return cached.colors
        }
        let colors = extractSwatches(from: artwork)
        swatchCache.setObject(SwatchList(colors), forKey: artwork)
        return colors
    }

    /// Reads a Music cover's pixels when it is in the library. Covers that
    /// would have to be downloaded fall back to the colours Music lists with
    /// the artwork, so the app itself makes no network request.
    static func swatches(of artwork: Artwork) async -> [PaletteColor] {
        if let url = artwork.url(width: 48, height: 48),
           url.scheme?.lowercased() != "https", url.scheme?.lowercased() != "http",
           let (data, _) = try? await URLSession.shared.data(from: url),
           let image = UIImage(data: data) {
            let colors = extractSwatches(from: image)
            if !colors.isEmpty {
                return colors
            }
        }
        return [artwork.backgroundColor, artwork.primaryTextColor, artwork.secondaryTextColor]
            .compactMap { $0.flatMap(PaletteColor.init) }
    }

    private static func extractSwatches(from artwork: MPMediaItemArtwork) -> [PaletteColor] {
        guard let image = artwork.image(at: CGSize(width: 96, height: 96)) else {
            return []
        }
        return extractSwatches(from: image)
    }

    private static func extractSwatches(from image: UIImage) -> [PaletteColor] {
        let side = 24
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return []
        }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            // Averaging rather than picking pixels gives the same colours
            // whatever size of the cover iOS returns.
            context.interpolationQuality = .high
            UIGraphicsPushContext(context)
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
            UIGraphicsPopContext()
            return true
        }
        return didDraw ? ArtworkSwatches.extract(fromRGBA: pixels) : []
    }
}

// MARK: - Screen theme

/// Colours that controls on a screen pick up. The accent is always the app's
/// ember; only secondary text takes a trace of the screen's artwork.
struct ScreenTheme {
    let accent = Color.ember
    let onAccent = Color("AccentForeground")
    var secondaryText: Color

    static let standard = ScreenTheme(secondaryText: Color("SecondaryText"))

    init(secondaryText: Color) {
        self.secondaryText = secondaryText
    }

    init(_ palette: ArtworkColorPalette) {
        self.init(secondaryText: Color(palette.secondaryText))
    }
}

private struct ScreenThemeKey: EnvironmentKey {
    static let defaultValue = ScreenTheme.standard
}

extension EnvironmentValues {
    var screenTheme: ScreenTheme {
        get { self[ScreenThemeKey.self] }
        set { self[ScreenThemeKey.self] = newValue }
    }
}

extension View {
    /// Tints secondary text with the palette; controls keep the ember.
    func screenTheme(_ palette: ArtworkColorPalette) -> some View {
        environment(\.screenTheme, ScreenTheme(palette))
            .tint(.ember)
    }
}

// MARK: - Colour field

extension EnvironmentValues {
    /// True under a sheet such as the full player or Settings, where a
    /// drifting field would animate unseen.
    @Entry var isCoveredBySheet = false
}

/// The app's signature surface: artwork colours as a slowly shifting field.
/// It drifts only while music plays and holds still with Reduce Motion.
/// Changing `arrangement` deals the colours into a new layout, so a
/// reshuffle visibly reshuffles the room.
struct ColorField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isCoveredBySheet) private var isCoveredBySheet
    @Environment(\.colorScheme) private var colorScheme
    let palette: ArtworkColorPalette
    var arrangement = 0
    var isPlaying = false
    /// Blends the lower edge into the ground colour for content below it.
    var fadesIntoGround = false
    @State private var clock = DriftClock()
    @State private var isOnScreen = false

    /// Drifting is decoration, so it stops for Reduce Motion and whenever the
    /// field can't be seen: under a pushed playlist or under a sheet.
    private var drifts: Bool {
        isPlaying && isOnScreen && !isCoveredBySheet && !reduceMotion
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !drifts)) { timeline in
            let layout = FieldLayout(
                palette: palette,
                arrangement: arrangement,
                phase: clock.phase(at: timeline.date),
                fadesIntoGround: fadesIntoGround
            )
            if #available(iOS 18.0, *) {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: layout.points,
                    colors: layout.colors,
                    background: Color(palette.ground)
                )
            } else {
                layout.fallbackGradient
            }
        }
        // An appearance switch crossfades the whole window, so the field
        // changes with it instead of easing into its new colours afterwards.
        .transaction(value: colorScheme) { transaction in
            transaction.animation = nil
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.3) : .smooth(duration: 1.1), value: arrangement)
        .animation(.easeInOut(duration: 0.8), value: palette)
        .onChange(of: drifts, initial: true) { _, drifts in
            clock.setRunning(drifts, at: .now)
        }
        .onAppear {
            isOnScreen = true
        }
        .onDisappear {
            isOnScreen = false
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Scrolling backdrop

/// Scroll position for a backdrop. It lives outside the view's own state so
/// scrolling redraws only the backdrop, not the list.
@MainActor
@Observable
final class ScrollTracker {
    var offset: CGFloat = 0
    /// The field holds still while the list moves, so scrolling never has
    /// to share frames with the drift.
    var isScrolling = false
}

extension View {
    /// Reports how far the list has scrolled. iOS 17 cannot read this, so
    /// the backdrop stays put there instead of scrolling with the header.
    @ViewBuilder
    func tracksScrollOffset(in tracker: ScrollTracker) -> some View {
        if #available(iOS 18.0, *) {
            // Past a screen's height the field is long gone, so further
            // scrolling stops redrawing it.
            onScrollGeometryChange(for: CGFloat.self) { geometry in
                min(geometry.contentOffset.y + geometry.contentInsets.top, 1_000)
            } action: { _, offset in
                tracker.offset = offset
            }
            .onScrollPhaseChange { _, phase in
                tracker.isScrolling = phase.isScrolling
            }
        } else {
            self
        }
    }
}

/// A colour field behind a screen's header, fading into its ground colour
/// beneath the list. It scrolls away with the header and stretches when the
/// list is pulled down.
struct ScrollingFieldBackdrop: View {
    let palette: ArtworkColorPalette
    let arrangement: Int
    let isPlaying: Bool
    let fieldHeight: CGFloat
    let scroll: ScrollTracker

    var body: some View {
        let offset = scroll.offset
        ColorField(
            palette: palette,
            arrangement: arrangement,
            isPlaying: isPlaying && !scroll.isScrolling,
            fadesIntoGround: true
        )
        .frame(height: fieldHeight + max(0, -offset))
        .offset(y: -max(0, offset))
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(palette.ground))
        .ignoresSafeArea()
    }
}

/// Accumulates only the time spent playing, so the field resumes where it
/// paused instead of jumping ahead.
private struct DriftClock {
    private var elapsed: TimeInterval = 0
    private var resumedAt: Date?

    func phase(at date: Date) -> TimeInterval {
        elapsed + (resumedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    mutating func setRunning(_ isRunning: Bool, at date: Date) {
        if isRunning, resumedAt == nil {
            resumedAt = date
        } else if !isRunning, let resumedAt {
            elapsed += date.timeIntervalSince(resumedAt)
            self.resumedAt = nil
        }
    }
}

/// A 3×3 mesh: corners stay pinned, the five inner points rest where the
/// arrangement puts them and wobble slowly around that spot.
private struct FieldLayout {
    let points: [SIMD2<Float>]
    let colors: [Color]
    private let center: UnitPoint

    init(palette: ArtworkColorPalette, arrangement: Int, phase: TimeInterval, fadesIntoGround: Bool) {
        var generator = SplitMix64(seed: UInt64(truncatingIfNeeded: arrangement))
        let field = [0, 1, 2, 3].shuffled(using: &generator).map { palette.field[$0] }
        let ground = palette.ground

        func restingOffset() -> Double {
            Double(generator.next() % 1_000) / 1_000 * 0.32 - 0.16
        }
        let anchors = (0..<5).map { _ in
            (x: restingOffset(), y: restingOffset(), phase: Double(generator.next() % 628) / 100)
        }
        func point(_ index: Int, speed: Double) -> (x: Double, y: Double) {
            let anchor = anchors[index]
            return (
                0.5 + anchor.x + 0.08 * sin(phase * speed + anchor.phase),
                0.5 + anchor.y + 0.08 * cos(phase * speed * 0.8 + anchor.phase)
            )
        }
        let top = point(0, speed: 0.31)
        let left = point(1, speed: 0.27)
        let middle = point(2, speed: 0.23)
        let right = point(3, speed: 0.29)
        let bottom = point(4, speed: 0.25)

        points = [
            [0, 0], [Float(top.x), 0], [1, 0],
            [0, Float(left.y)], [Float(middle.x), Float(middle.y)], [1, Float(right.y)],
            [0, 1], [Float(bottom.x), 1], [1, 1],
        ]
        center = UnitPoint(x: middle.x, y: middle.y)

        let blend = field[0].mixed(with: field[2], amount: 0.5)
        let lowerRow = fadesIntoGround
            ? [ground, ground, ground]
            : [field[2], field[3], field[0]]
        colors = ([field[0], field[1], field[2], field[3], blend, field[1]] + lowerRow).map(Color.init)
    }

    /// iOS 17 has no mesh gradient; layered gradients give a calmer version.
    var fallbackGradient: some View {
        ZStack {
            LinearGradient(colors: [colors[0], colors[2]], startPoint: .topLeading, endPoint: .topTrailing)
            RadialGradient(
                colors: [colors[4], colors[4].opacity(0)],
                center: center,
                startRadius: 0,
                endRadius: 360
            )
            LinearGradient(colors: [colors[7].opacity(0), colors[7]], startPoint: .center, endPoint: .bottom)
        }
    }
}

/// Small deterministic generator so an arrangement always deals the same way.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
