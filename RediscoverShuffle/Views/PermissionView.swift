import MediaPlayer
import SwiftUI
import UIKit

struct PermissionView: View {
    @EnvironmentObject private var libraryService: MusicLibraryService
    @Environment(\.openURL) private var openURL
    @AppStorage(SettingsKeys.hasShownOnboarding) private var hasShownOnboarding = false

    private var isDenied: Bool {
        libraryService.authorizationStatus == .denied
    }

    private var isRestricted: Bool {
        libraryService.authorizationStatus == .restricted
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 48)

                Image(systemName: isDenied || isRestricted ? "music.note.list" : "shuffle.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("Rediscover Shuffle")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)

                    Text(headline)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text(explanation)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                privacyExplanation

                if libraryService.isLoading {
                    ProgressView("Waiting for permission…")
                } else if libraryService.authorizationStatus == .notDetermined {
                    Button {
                        hasShownOnboarding = true
                        libraryService.requestAuthorization()
                    } label: {
                        Label("Continue", systemImage: "music.note")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint("Shows the system prompt for Music library access")
                } else if isDenied || isRestricted {
                    Button {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    } label: {
                        Label("Open Settings", systemImage: "gear")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint("Opens this app's page in Settings")
                }

                Text("Your library information and shuffle calculations stay on this iPhone. The app does not use analytics or a server.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 24)
            }
            .frame(maxWidth: 540)
            .padding(.horizontal, 28)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var headline: String {
        switch libraryService.authorizationStatus {
        case .denied:
            return "Music access is turned off"
        case .restricted:
            return "Music access is restricted"
        default:
            return hasShownOnboarding ? "Music library access is needed" : "Give overlooked songs another chance"
        }
    }

    private var explanation: String {
        switch libraryService.authorizationStatus {
        case .denied:
            return "Allow Music access in Settings, then return here to browse your playlists."
        case .restricted:
            return "This iPhone currently prevents access to the Music library. A device restriction or parental control may need to be changed."
        default:
            return "Choose one of your Music library playlists. Songs you have played less often will be more likely to appear early, while every result remains random."
        }
    }

    private var privacyExplanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Show playlists already in your library", systemImage: "music.note.list")
            Label("Read play counts to weight the shuffle", systemImage: "chart.bar")
            Label("Send the finished order to the Music app", systemImage: "play.circle")
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
