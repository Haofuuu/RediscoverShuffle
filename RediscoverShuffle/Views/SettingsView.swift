import MediaPlayer
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var libraryService: MusicLibraryService

    @AppStorage(SettingsKeys.appearance) private var appearanceRawValue = AppAppearance.defaultValue.rawValue
    @AppStorage(SettingsKeys.showPlayCounts) private var showPlayCounts = AppSettingDefaults.showPlayCounts

    private let metadata = AppMetadata()

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: appearanceBinding) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .sensoryFeedback(.selection, trigger: appearanceRawValue)
            }

            Section {
                Toggle(isOn: $showPlayCounts) {
                    Label("Show Play Counts", systemImage: "number")
                }
            } footer: {
                Text("Rediscovery strength and song sort are set on each playlist’s screen.")
            }

            Section {
                Button(action: openAppSettings) {
                    HStack {
                        Label("Language", systemImage: "globe")
                        Spacer(minLength: 12)
                        Image(systemName: "arrow.up.forward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityHint("Opens this app’s page in iOS Settings, where you can choose its language")
            }

            if libraryService.authorizationStatus != .authorized {
                Section {
                    LabeledContent {
                        Text(musicAuthorizationDescription)
                            .foregroundStyle(Color("SecondaryText"))
                    } label: {
                        Label("Music Library", systemImage: "music.note.list")
                    }

                    if libraryService.authorizationStatus == .denied
                        || libraryService.authorizationStatus == .restricted {
                        Button(action: openAppSettings) {
                            Label("Open iOS Settings", systemImage: "gear")
                        }
                    }
                } header: {
                    Text("Music Access")
                }
            }

            #if DEBUG
            TouchInspectorSettingsSection()
            #endif

            Section {
                LabeledContent("Version", value: metadata.versionAndBuild)

                Link(destination: Self.repositoryURL) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            } header: {
                Text("About")
            } footer: {
                Label {
                    Text("Your library and every shuffle stay on this iPhone. No analytics, no servers.")
                } icon: {
                    Image(systemName: "lock.shield")
                        .accessibilityHidden(true)
                }
                .padding(.top, 4)
            }
        }
        .listSectionSpacing(24)
        .textCase(nil)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance.resolved(rawValue: appearanceRawValue) },
            set: { appearanceRawValue = $0.rawValue }
        )
    }

    private var musicAuthorizationDescription: String {
        switch libraryService.authorizationStatus {
        case .notDetermined: return String(localized: "Not Requested")
        case .denied: return String(localized: "Denied")
        case .restricted: return String(localized: "Restricted")
        case .authorized: return String(localized: "Authorized")
        @unknown default: return String(localized: "Unknown")
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        openURL(url)
    }

    private static let repositoryURL = URL(string: "https://github.com/Haofuuu/RediscoverShuffle")!
}

private struct AppMetadata {
    let versionAndBuild: String

    init(bundle: Bundle = .main) {
        let version = Self.nonempty(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? String(localized: "Unknown")
        let build = Self.nonempty(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            ?? String(localized: "Unknown")
        versionAndBuild = "\(version) (\(build))"
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
