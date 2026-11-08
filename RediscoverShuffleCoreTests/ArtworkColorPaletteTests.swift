import Testing
@testable import RediscoverShuffleCore

@Suite("Artwork colour palette")
struct ArtworkColorPaletteTests {
    private static let ember = PaletteColor(red: 0.78, green: 0.2, blue: 0.25)

    @Test("HSB values round-trip through RGB")
    func hsbRoundTrip() {
        let color = PaletteColor(hue: 0.62, saturation: 0.7, brightness: 0.8)
        #expect(abs(color.hue - 0.62) < 0.001)
        #expect(abs(color.saturation - 0.7) < 0.001)
        #expect(abs(color.brightness - 0.8) < 0.001)
    }

    @Test("Contrast ratio follows WCAG")
    func contrastRatio() {
        #expect(abs(PaletteColor.white.contrastRatio(with: .black) - 21) < 0.001)
        #expect(PaletteColor.white.contrastRatio(with: .white) == 1)
    }

    @Test("The most prominent colour comes first")
    func swatchOrder() {
        let red: [UInt8] = [220, 40, 40, 255]
        let blue: [UInt8] = [40, 60, 210, 255]
        let pixels = Array(repeating: red, count: 70).flatMap { $0 }
            + Array(repeating: blue, count: 30).flatMap { $0 }

        let swatches = ArtworkSwatches.extract(fromRGBA: pixels)

        #expect(swatches.count == 2)
        #expect(swatches[0].red > swatches[0].blue)
        #expect(swatches[1].blue > swatches[1].red)
    }

    @Test("Transparent pixels and empty images give no swatches")
    func transparentPixels() {
        #expect(ArtworkSwatches.extract(fromRGBA: []).isEmpty)
        #expect(ArtworkSwatches.extract(fromRGBA: [255, 0, 0, 0, 0, 255, 0, 10]).isEmpty)
    }

    @Test("Near-identical shades collapse into one swatch")
    func similarShades() {
        let pixels: [UInt8] = Array(repeating: [200, 60, 60, 255], count: 50).flatMap { $0 }
            + Array(repeating: [206, 66, 62, 255], count: 50).flatMap { $0 }
        #expect(ArtworkSwatches.extract(fromRGBA: pixels).count == 1)
    }

    @Test(
        "Every role stays readable",
        arguments: [
            [PaletteColor(red: 0.95, green: 0.85, blue: 0.1)],
            [PaletteColor(red: 0.1, green: 0.2, blue: 0.85), PaletteColor(red: 0.9, green: 0.4, blue: 0.1)],
            [PaletteColor(red: 0.05, green: 0.05, blue: 0.05), PaletteColor(red: 0.85, green: 0.1, blue: 0.2)],
            [PaletteColor(red: 0.97, green: 0.97, blue: 0.95)],
            [PaletteColor(red: 0.3, green: 0.8, blue: 0.35), PaletteColor(red: 0.2, green: 0.7, blue: 0.9)],
            [],
        ]
    )
    func readableRoles(swatches: [PaletteColor]) {
        for appearance in [ArtworkColorPalette.Appearance.light, .dark] {
            let palette = ArtworkColorPalette(swatches: swatches, fallback: Self.ember, appearance: appearance)
            let primaryText: PaletteColor = appearance == .dark ? .white : .black
            let surfaces = palette.field + [palette.ground]

            #expect(palette.field.count == 4)
            #expect(primaryText.contrastRatio(with: palette.ground) >= 7)
            for surface in surfaces {
                #expect(primaryText.contrastRatio(with: surface) >= 7)
                #expect(palette.secondaryText.contrastRatio(with: surface) >= 4.5)
            }
        }
    }

    @Test(
        "Secondary text stays grey on vivid artwork",
        arguments: [
            PaletteColor(red: 0.95, green: 0.45, blue: 0.1),
            PaletteColor(red: 0.95, green: 0.3, blue: 0.55),
            PaletteColor(red: 0.2, green: 0.8, blue: 0.3),
        ]
    )
    func secondaryTextStaysGrey(swatch: PaletteColor) {
        for appearance in [ArtworkColorPalette.Appearance.light, .dark] {
            let palette = ArtworkColorPalette(swatches: [swatch], fallback: Self.ember, appearance: appearance)
            #expect(palette.secondaryText.saturation <= ArtworkColorPalette.secondaryTint + 0.001)
        }
    }

    @Test("Grey artwork keeps a neutral page")
    func monochromeArtwork() {
        let greys = [PaletteColor(red: 0.5, green: 0.5, blue: 0.5), PaletteColor(red: 0.15, green: 0.15, blue: 0.15)]
        let palette = ArtworkColorPalette(swatches: greys, fallback: Self.ember, appearance: .dark)

        #expect(palette.ground.saturation < 0.01)
        #expect(palette.secondaryText.saturation < 0.01)
    }

    @Test("A near-black with a faint tint stays neutral")
    func faintlyTintedBlack() {
        let nearBlack = PaletteColor(red: 0.12, green: 0.1, blue: 0.12)
        let palette = ArtworkColorPalette(swatches: [Self.ember, nearBlack], fallback: Self.ember, appearance: .dark)

        #expect(palette.field.allSatisfy { $0.saturation < 0.2 || Self.hueDistance($0.hue, Self.ember.hue) < 0.1 })
    }

    /// Hue is circular: 0.98 and 0.02 are neighbours.
    private static func hueDistance(_ first: Double, _ second: Double) -> Double {
        let distance = abs(first - second)
        return min(distance, 1 - distance)
    }

    @Test("A single colour still fills a varied field")
    func singleSwatchField() {
        let palette = ArtworkColorPalette(
            swatches: [PaletteColor(red: 0.2, green: 0.5, blue: 0.9)],
            fallback: Self.ember,
            appearance: .dark
        )
        #expect(Set(palette.field).count == 4)
    }
}
