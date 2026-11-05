import Foundation

/// An sRGB colour with components from 0 to 1. It stays free of UIKit and
/// SwiftUI so the palette rules can be tested on any platform.
struct PaletteColor: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    static let white = PaletteColor(red: 1, green: 1, blue: 1)
    static let black = PaletteColor(red: 0, green: 0, blue: 0)

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    init(hue: Double, saturation: Double, brightness: Double) {
        let sector = (hue - hue.rounded(.down)) * 6
        let value = min(max(brightness, 0), 1)
        let chroma = value * min(max(saturation, 0), 1)
        let secondary = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let match = value - chroma
        let (red, green, blue): (Double, Double, Double) = switch sector {
        case ..<1: (chroma, secondary, 0)
        case ..<2: (secondary, chroma, 0)
        case ..<3: (0, chroma, secondary)
        case ..<4: (0, secondary, chroma)
        case ..<5: (secondary, 0, chroma)
        default: (chroma, 0, secondary)
        }
        self.init(red: red + match, green: green + match, blue: blue + match)
    }

    var hue: Double {
        let maximum = max(red, green, blue)
        let delta = maximum - min(red, green, blue)
        guard delta > 0 else {
            return 0
        }
        let sector: Double = switch maximum {
        case red: (green - blue) / delta
        case green: (blue - red) / delta + 2
        default: (red - green) / delta + 4
        }
        let hue = sector / 6
        return hue < 0 ? hue + 1 : hue
    }

    var saturation: Double {
        let maximum = max(red, green, blue)
        return maximum == 0 ? 0 : (maximum - min(red, green, blue)) / maximum
    }

    var brightness: Double {
        max(red, green, blue)
    }

    /// WCAG 2 relative luminance.
    var relativeLuminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func contrastRatio(with other: PaletteColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    func mixed(with other: PaletteColor, amount: Double) -> PaletteColor {
        PaletteColor(
            red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount
        )
    }

    func with(saturation: Double? = nil, brightness: Double? = nil) -> PaletteColor {
        PaletteColor(
            hue: hue,
            saturation: saturation ?? self.saturation,
            brightness: brightness ?? self.brightness
        )
    }

    /// Greys, near-blacks, and near-whites. Chroma is checked as well as
    /// saturation because saturation exaggerates the faint tint of very
    /// dark colours.
    fileprivate var isNeutral: Bool {
        saturation < 0.15 || max(red, green, blue) - min(red, green, blue) < 0.08
    }

    fileprivate func distance(to other: PaletteColor) -> Double {
        let red = self.red - other.red
        let green = self.green - other.green
        let blue = self.blue - other.blue
        return (red * red + green * green + blue * blue).squareRoot()
    }
}

/// Finds the handful of colours that characterise a piece of artwork.
enum ArtworkSwatches {
    /// Returns up to `maximumCount` distinct colours, most prominent first.
    /// `rgba` holds 8-bit RGBA pixels, usually from a small thumbnail.
    /// Colourful areas count a little more than grey ones, so a small red
    /// logo on a large grey cover still makes it into the palette.
    static func extract(fromRGBA rgba: [UInt8], maximumCount: Int = 3) -> [PaletteColor] {
        struct Bucket {
            var red = 0.0
            var green = 0.0
            var blue = 0.0
            var count = 0.0
            var weight = 0.0
        }

        var buckets: [Int: Bucket] = [:]
        var index = 0
        while index + 3 < rgba.count {
            defer { index += 4 }
            guard rgba[index + 3] >= 128 else {
                continue
            }
            let color = PaletteColor(
                red: Double(rgba[index]) / 255,
                green: Double(rgba[index + 1]) / 255,
                blue: Double(rgba[index + 2]) / 255
            )
            let shade = min(Int(color.brightness * 3), 2)
            let key: Int
            let weight: Double
            if color.isNeutral {
                key = 100 + shade
                weight = 0.5
            } else {
                key = (Int(color.hue * 12) % 12) * 3 + shade
                weight = 0.6 + color.saturation
            }
            var bucket = buckets[key, default: Bucket()]
            bucket.red += color.red
            bucket.green += color.green
            bucket.blue += color.blue
            bucket.count += 1
            bucket.weight += weight
            buckets[key] = bucket
        }

        let ranked = buckets.sorted { left, right in
            left.value.weight == right.value.weight
                ? left.key < right.key
                : left.value.weight > right.value.weight
        }

        var swatches: [PaletteColor] = []
        for (_, bucket) in ranked where swatches.count < maximumCount {
            let average = PaletteColor(
                red: bucket.red / bucket.count,
                green: bucket.green / bucket.count,
                blue: bucket.blue / bucket.count
            )
            if swatches.allSatisfy({ $0.distance(to: average) > 0.16 }) {
                swatches.append(average)
            }
        }
        return swatches
    }
}

/// Colour roles for a screen themed by its artwork: a moving field, the calm
/// page it fades into, and secondary text that stays readable on both.
/// Controls don't take their colour from here: every screen shares the app
/// icon's ember, so the artwork sets the room, not the buttons.
struct ArtworkColorPalette: Equatable, Sendable {
    enum Appearance: Sendable {
        case light
        case dark
    }

    /// Four colours for the field, tuned so primary text reads on each.
    let field: [PaletteColor]
    let ground: PaletteColor
    /// A grey with a trace of the artwork's hue, so it sits in the room
    /// without reading as a second accent.
    let secondaryText: PaletteColor

    /// `fallback` stands in for artwork that has no colours of its own.
    init(swatches: [PaletteColor], fallback: PaletteColor, appearance: Appearance) {
        let sources = swatches.isEmpty ? [fallback] : swatches
        let colorful = sources.filter { !$0.isNeutral }
        let tintSource = colorful.first ?? sources[0]
        let isMonochrome = colorful.isEmpty

        // Short palettes are filled out with near neighbours of what is there,
        // so a single-colour cover still gets a field with some depth.
        let hueShifts = [0, -0.05, 0.05, 0.09]
        let brightnessScales = [1, 0.78, 1.12, 0.92]
        var fieldSources = Array(sources.prefix(3))
        let distinctCount = fieldSources.count
        while fieldSources.count < 4 {
            let slot = fieldSources.count
            let neighbour = fieldSources[slot % distinctCount]
            fieldSources.append(
                PaletteColor(
                    hue: neighbour.hue + (neighbour.isNeutral ? 0 : hueShifts[slot]),
                    saturation: neighbour.saturation,
                    brightness: neighbour.brightness * brightnessScales[slot]
                )
            )
        }

        let primaryText: PaletteColor = appearance == .dark ? .white : .black
        field = fieldSources.map { source in
            Self.fieldColor(from: source, appearance: appearance, primaryText: primaryText)
        }

        ground = switch appearance {
        case .dark:
            PaletteColor(
                hue: tintSource.hue,
                saturation: isMonochrome ? tintSource.saturation * 0.5 : min(tintSource.saturation, 0.55) * 0.7,
                brightness: 0.11
            )
        case .light:
            PaletteColor(
                hue: tintSource.hue,
                saturation: isMonochrome ? 0 : min(tintSource.saturation, 0.5) * 0.12,
                brightness: 0.985
            )
        }

        let surfaces = field + [ground]
        func reads(_ candidate: PaletteColor, at ratio: Double) -> Bool {
            surfaces.allSatisfy { candidate.contrastRatio(with: $0) >= ratio }
        }

        secondaryText = switch appearance {
        case .dark:
            Self.adjusted(
                PaletteColor(hue: tintSource.hue, saturation: min(tintSource.saturation, Self.secondaryTint), brightness: 0.8),
                until: { reads($0, at: 4.5) },
                step: { $0.with(saturation: $0.saturation - 0.02, brightness: $0.brightness + 0.03) }
            )
        case .light:
            Self.adjusted(
                PaletteColor(hue: tintSource.hue, saturation: min(tintSource.saturation, Self.secondaryTint), brightness: 0.4),
                until: { reads($0, at: 4.5) },
                step: { $0.with(brightness: $0.brightness - 0.03) }
            )
        }
    }

    /// The most colour secondary text may carry. Above this it starts to read
    /// as pink, orange, or green text rather than grey.
    static let secondaryTint = 0.12

    /// Keeps the artwork's hue but holds brightness in a band where primary
    /// text stays comfortably readable: deep in dark mode, airy in light mode.
    private static func fieldColor(
        from source: PaletteColor,
        appearance: Appearance,
        primaryText: PaletteColor
    ) -> PaletteColor {
        switch appearance {
        case .dark:
            let start = source.with(
                saturation: source.isNeutral ? source.saturation : min(max(source.saturation, 0.45), 0.85),
                brightness: min(max(source.brightness, 0.24), 0.5)
            )
            return adjusted(
                start,
                until: { $0.contrastRatio(with: primaryText) >= 7 },
                step: { $0.with(brightness: $0.brightness - 0.02) }
            )
        case .light:
            let start = source.with(
                saturation: source.isNeutral ? source.saturation : min(max(source.saturation, 0.22), 0.5),
                brightness: min(max(source.brightness, 0.86), 0.97)
            )
            return adjusted(
                start,
                until: { $0.contrastRatio(with: primaryText) >= 9 },
                step: { $0.with(saturation: $0.saturation - 0.03, brightness: $0.brightness + 0.01) }
            )
        }
    }

    private static func adjusted(
        _ color: PaletteColor,
        until isAcceptable: (PaletteColor) -> Bool,
        step: (PaletteColor) -> PaletteColor
    ) -> PaletteColor {
        var candidate = color
        var attempts = 0
        while !isAcceptable(candidate), attempts < 40 {
            candidate = step(candidate)
            attempts += 1
        }
        return candidate
    }
}
