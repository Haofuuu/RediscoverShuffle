import MediaPlayer
import SwiftUI
import UIKit

struct PermissionView: View {
    @EnvironmentObject private var libraryService: MusicLibraryService
    @Environment(\.openURL) private var openURL
    @AppStorage(SettingsKeys.hasShownOnboarding) private var hasShownOnboarding = false
    @State private var showsSettings = false
    @State private var hasAppeared = false
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize = 84

    private var isDenied: Bool {
        libraryService.authorizationStatus == .denied
    }

    private var isRestricted: Bool {
        libraryService.authorizationStatus == .restricted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 12)

                Image("AppIconImage")
                    .resizable()
                    .frame(width: min(iconSize, 112), height: min(iconSize, 112))
                    .clipShape(RoundedRectangle(cornerRadius: min(iconSize, 112) * 0.2237, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: min(iconSize, 112) * 0.2237, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    }
                    .shadow(color: Color("AccentColor").opacity(0.35), radius: 22, y: 10)
                    .accessibilityHidden(true)
                    .entrance(order: 0, isVisible: hasAppeared)

                VStack(alignment: .leading, spacing: 12) {
                    Text(headline)
                        .font(.largeTitle.bold())
                        .tracking(-0.6)
                        .accessibilityAddTraits(.isHeader)

                    Text(explanation)
                        .font(.body)
                        .foregroundStyle(Color("SecondaryText"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .entrance(order: 1, isVisible: hasAppeared)

                privacyExplanation
                    .entrance(order: 2, isVisible: hasAppeared)

                Label {
                    Text("Your library and every shuffle stay on this iPhone. No analytics, no servers.")
                } icon: {
                    Image(systemName: "lock.shield")
                        .accessibilityHidden(true)
                }
                    .font(.footnote)
                    .foregroundStyle(Color("SecondaryText"))
                    .fixedSize(horizontal: false, vertical: true)
                    .entrance(order: 3, isVisible: hasAppeared)

                Spacer(minLength: 24)
            }
            .frame(maxWidth: 540)
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
        }
        .background(alignment: .top) {
            ArtworkGlowBackground(color: nil)
                .frame(height: 420)
                .ignoresSafeArea()
        }
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom) {
            permissionAction
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
        }
        .onAppear {
            hasAppeared = true
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityHint("Opens Rediscover Shuffle settings")
            }
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                SettingsView()
            }
        }
    }

    @ViewBuilder
    private var permissionAction: some View {
        if libraryService.isLoading {
            ProgressView("Waiting for permission…")
                .frame(maxWidth: .infinity, minHeight: 52)
        } else if libraryService.authorizationStatus == .notDetermined {
            Button {
                hasShownOnboarding = true
                libraryService.requestAuthorization()
            } label: {
                CenteredActionLabel(title: String(localized: "Get Started"), systemImage: "arrow.forward")
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .accessibilityHint("Shows the system prompt for Music library access")
        } else if isDenied || isRestricted {
            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            } label: {
                CenteredActionLabel(title: String(localized: "Open Settings"), systemImage: "gear")
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .accessibilityHint("Opens this app's page in Settings")
        }
    }

    private var headline: String {
        switch libraryService.authorizationStatus {
        case .denied:
            return String(localized: "Music access is turned off")
        case .restricted:
            return String(localized: "Music access is restricted")
        default:
            return hasShownOnboarding
                ? String(localized: "One step left: allow Music access")
                : String(localized: "Give overlooked songs another chance")
        }
    }

    private var explanation: String {
        switch libraryService.authorizationStatus {
        case .denied:
            return String(localized: "Allow Music access in Settings, then return here to browse your playlists.")
        case .restricted:
            return String(localized: "This iPhone currently prevents access to the Music library. A device restriction or parental control may need to be changed.")
        default:
            return String(localized: "Pick a playlist and Rediscover Shuffle brings the songs you rarely play closer to the top. Every order is still random.")
        }
    }

    private var privacyExplanation: some View {
        VStack(alignment: .leading, spacing: 18) {
            featureRow(String(localized: "Shows the playlists already in your library"), systemImage: "music.note.list")
            featureRow(String(localized: "Reads play counts to find overlooked songs"), systemImage: "sparkles")
            featureRow(String(localized: "Plays the new order in the Music app"), systemImage: "play.fill")
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func featureRow(_ title: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color("AccentColor"))
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// First-run entrance: each block rises 10pt and fades in, 60ms after the
/// previous one. With Reduce Motion it only fades.
private struct EntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let order: Int
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 10)
            .animation(.strongEaseOut(duration: 0.5).delay(Double(order) * 0.06), value: isVisible)
    }
}

private extension View {
    func entrance(order: Int, isVisible: Bool) -> some View {
        modifier(EntranceModifier(order: order, isVisible: isVisible))
    }
}
