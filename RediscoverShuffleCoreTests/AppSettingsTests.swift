import Testing
@testable import RediscoverShuffleCore

@Suite("App settings")
struct AppSettingsTests {
    @Test("Appearance falls back to System for an unknown raw value")
    func appearanceFallback() {
        #expect(AppAppearance.resolved(rawValue: "future-value") == .system)
        #expect(AppAppearance.resolved(rawValue: AppAppearance.dark.rawValue) == .dark)
    }

    @Test("Song sort falls back to default playlist order")
    func songSortFallback() {
        #expect(PlaylistSongSortOption.resolved(rawValue: "future-value") == .defaultOrder)
        #expect(
            PlaylistSongSortOption.resolved(rawValue: PlaylistSongSortOption.playsHighToLow.rawValue)
                == .playsHighToLow
        )
    }

    @Test("Settings defaults remain stable")
    func defaultValues() {
        #expect(AppAppearance.defaultValue == .system)
        #expect(PlaylistSongSortOption.defaultValue == .defaultOrder)
        #expect(RediscoveryStrengthSetting.defaultValue == 1.0)
        #expect(AppSettingDefaults.showPlayCounts)
        #expect(RediscoveryStrengthSetting.allowedValues == [0, 1, 2, 3, 4, 5])
    }

    @Test("Rediscovery strength normalization uses the persisted default")
    func strengthNormalization() {
        #expect(RediscoveryStrengthSetting.normalized(.nan) == 1.0)
        #expect(RediscoveryStrengthSetting.normalized(-4.0) == 0.0)
        #expect(RediscoveryStrengthSetting.normalized(8.0) == 5.0)
        #expect(RediscoveryStrengthSetting.normalized(2.6) == 3.0)
    }
}
