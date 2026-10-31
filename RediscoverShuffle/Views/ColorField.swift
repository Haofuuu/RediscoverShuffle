import MediaPlayer
import SwiftUI
import UIKit

// MARK: - Palettes from artwork

extension Color {
    init(_ color: PaletteColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue)
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
    /// The app's ember, used when artwork has no colour to offer.
    static let fallbackAccent = PaletteColor(red: 0.784, green: 0.196, blue: 0.247)

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

    /// The app icon's world: ember glowing out of near-black, with a deep
    /// wine between them. Used where there is no artwork yet, such as
    /// onboarding.
    static func brand(appearance: ArtworkColorPalette.Appearance) -> ArtworkColorPalette {
        palette(
            swatches: [
                fallbackAccent,
                PaletteColor(red: 0.12, green: 0.1, blue: 0.12),
                PaletteColor(red: 0.45, green: 0.08, blue: 0.16),
            ],
            appearance: appearance
        )
    }

    static func palette(
        for playlist: LibraryPlaylist,
        appearance: ArtworkColorPalette.Appearance
    ) -> ArtworkColorPalette {
        palette(swatches: swatches(for: playlist), appearance: appearance)
    }

    static func palette(
        for artwork: MPMediaItemArtwork?,
        appearance: ArtworkColorPalette.Appearance
    ) -> ArtworkColorPalette {
        palette(swatches: artwork.map(swatches(of:)) ?? [], appearance: appearance)
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
            fallbackAccent: fallbackAccent,
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

    private static func extractSwatches(from artwork: MPMediaItemArtwork) -> [PaletteColor] {
        let side = 24
        guard let image = artwork.image(at: CGSize(width: side * 2, height: side * 2)),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
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
            UIGraphicsPushContext(context)
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
            UIGraphicsPopContext()
            return true
        }
        return didDraw ? ArtworkSwatches.extract(fromRGBA: pixels) : []
    }
}

// MARK: - Screen theme

/// Colours that controls on a screen pick up: the app's ember by default,
/// the artwork's own colours inside a playlist or the player.
struct ScreenTheme {
    var accent: Color
    var onAccent: Color
    var accentText: Color
    var secondaryText: Color

    static let standard = ScreenTheme(
        accent: Color("AccentColor"),
        onAccent: Color("AccentForeground"),
        accentText: Color("AccentColor"),
        secondaryText: Color("SecondaryText")
    )

    init(accent: Color, onAccent: Color, accentText: Color, secondaryText: Color) {
        self.accent = accent
        self.onAccent = onAccent
        self.accentText = accentText
        self.secondaryText = secondaryText
    }

    init(_ palette: ArtworkColorPalette) {
        self.init(
            accent: Color(palette.accent),
            onAccent: Color(palette.onAccent),
            accentText: Color(palette.accentText),
            secondaryText: Color(palette.secondaryText)
        )
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
    /// Themes buttons, badges, and secondary text with the palette's colours.
    func screenTheme(_ palette: ArtworkColorPalette) -> some View {
        environment(\.screenTheme, ScreenTheme(palette))
            .tint(Color(palette.accentText))
    }
}

// MARK: - Colour field

/// The app's signature surface: artwork colours as a slowly shifting field.
/// It drifts only while music plays and holds still with Reduce Motion.
/// Changing `arrangement` deals the colours into a new layout, so a
/// reshuffle visibly reshuffles the room.
struct ColorField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let palette: ArtworkColorPalette
    var arrangement = 0
    var isPlaying = false
    /// Blends the lower edge into the ground colour for content below it.
    var fadesIntoGround = false
    @State private var clock = DriftClock()
    @State private var isOnScreen = false

    /// Drifting is decoration, so it stops for Reduce Motion and whenever the
    /// field is off screen, such as under a pushed playlist.
    private var drifts: Bool {
        isPlaying && isOnScreen && !reduceMotion
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
