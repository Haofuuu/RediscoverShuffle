import Foundation

enum SettingsKeys {
    static let appearance = "appearance"
    static let rediscoveryStrength = "rediscoveryStrength"
    static let playlistSongSortOption = "playlistSongSortOption"
    static let showPlayCounts = "showPlayCounts"
    static let lastSelectedPlaylistID = "lastSelectedPlaylistPersistentID"
    static let hasShownOnboarding = "hasShownOnboarding"
    static let pinnedPlaylistIDs = "pinnedPlaylistPersistentIDs"
}

enum AppAppearance: String, CaseIterable, Hashable, Identifiable {
    case system
    case light
    case dark

    static let defaultValue = AppAppearance.system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }

    static func resolved(rawValue: String) -> AppAppearance {
        AppAppearance(rawValue: rawValue) ?? defaultValue
    }
}

enum RediscoveryStrengthSetting {
    static let defaultValue = 1.0
    static let allowedValues = Array(
        Int(WeightedShuffleEngine.supportedBiasRange.lowerBound)
            ... Int(WeightedShuffleEngine.supportedBiasRange.upperBound)
    )

    static func normalized(_ value: Double) -> Double {
        guard value.isFinite else {
            return defaultValue
        }
        return min(
            max(value.rounded(), WeightedShuffleEngine.supportedBiasRange.lowerBound),
            WeightedShuffleEngine.supportedBiasRange.upperBound
        )
    }

    static func name(for value: Double) -> String {
        switch Int(normalized(value)) {
        case 0: return String(localized: "Off")
        case 1: return String(localized: "Gentle")
        case 2: return String(localized: "Moderate")
        case 3: return String(localized: "Strong")
        case 4: return String(localized: "Very Strong")
        default: return String(localized: "Maximum")
        }
    }
}

enum AppSettingDefaults {
    static let showPlayCounts = true
}
