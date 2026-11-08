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

// MARK: - Transitions

extension View {
    /// Marks the view a zoom transition grows from. Zoom transitions need
    /// iOS 18; earlier versions keep the standard push.
    @ViewBuilder
    func zoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Presents this screen by zooming out of the matching `zoomSource`, or
    /// with the standard push before iOS 18. Once the screen starts going
    /// away, it takes no taps.
    @ViewBuilder
    func zoomTransition(from id: some Hashable, in namespace: Namespace.ID) -> some View {
        let guarded = modifier(LeavingScreenGuard())
        if #available(iOS 18.0, *) {
            guarded.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            guarded
        }
    }
}

extension EnvironmentValues {
    /// Whether a zoomed screen is settled, for its buttons to check when
    /// tapped.
    @Entry var screenArrival: ScreenArrival?
}

/// Whether a screen is settled: from the start of a fresh opening until it
/// is grabbed to be swiped away or starts going away. A plain object rather
/// than SwiftUI state: once SwiftUI starts removing a screen it stops
/// updating it, so new state never reaches the screen's buttons, but a
/// button can still read this the moment it is tapped.
@MainActor
final class ScreenArrival {
    fileprivate(set) var isSettled = false
    /// Told when the screen starts going away and when it has gone.
    var onDeparture: ((Departure) -> Void)?
    /// Takes the screen back, as its Back button does.
    var goBack: (() -> Void)?

    enum Departure {
        case started
        case finished
    }
}

/// SwiftUI's zoom is interruptible: taps keep working while a screen zooms,
/// so tapping the playlist again reopens it and tapping anything else on the
/// main page goes where it was aimed. A screen that is going away must not
/// answer any of those taps, or its buttons and popovers would turn up over
/// the main page.
///
/// A screen can go away two ways: popped after it arrived, or swiped away
/// while still zooming open, which cancels the opening and never pops it.
/// SwiftUI stops updating a screen it removes, so `isPresented`,
/// `allowsHitTesting`, and state changes arrive too late. This follows UIKit
/// instead: the screen counts as settled only between arriving and starting
/// to leave, and once it is going away its view stops taking touches (for a
/// swipe, once the finger lets go). A cancelled pop gives them back.
///
/// The zoom's own swipes, from the leading edge or downward, follow the
/// finger and can catch a screen that is still opening, as in Music. When
/// such a swipe cancels an opening, the screen glides back to its row in
/// about a quarter of a second, but iOS only reports it gone about a second
/// later, and until then SwiftUI still counts it as open and ignores taps
/// that would open it again. So once the glide has had time to land, the
/// screen is released; that skips only the invisible end of the animation.
///
/// That second-long tail also means the screen looks fully open well before
/// iOS stops counting it as opening, and a swipe from the edge in that time
/// cancelled the opening rather than going back, with the same pause before
/// taps work. So once the zoom-in has visibly landed, the zoom's own swipes
/// pause until iOS reports the opening finished, and a swipe from the edge
/// goes back the way any other swipe does.
///
/// The zoom only lets a swipe back start at the edge. A quick swipe toward
/// the trailing edge from anywhere else goes back too, through SwiftUI as the
/// Back button does: popping in UIKit directly left SwiftUI counting the
/// screen as open until the zoom back ended, so tapping the same playlist
/// couldn't catch it. A pop during the zoom-in makes iOS snap the screen
/// fully open first, so such a swipe waits until the zoom-in has visibly
/// landed.
private struct LeavingScreenGuard: ViewModifier {
    @State private var arrival = ScreenArrival()

    func body(content: Content) -> some View {
        content
            .environment(\.screenArrival, arrival)
            .background {
                ScreenTransitionObserver(arrival: arrival)
                    .accessibilityHidden(true)
            }
    }
}

private struct ScreenTransitionObserver: UIViewControllerRepresentable {
    let arrival: ScreenArrival

    func makeUIViewController(context: Context) -> Controller {
        Controller(arrival: arrival)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private let arrival: ScreenArrival
        /// The screen whose touches this switched off, to give them back.
        private weak var heldScreen: UIViewController?
        /// A swipe back from anywhere on the screen.
        private var swipeBack: UIPanGestureRecognizer?
        private weak var swipeBackScreen: UIViewController?
        /// An opening that a swipe cancelled and iOS hasn't finished yet.
        private var isFinishingCancelledOpening = false
        /// When the screen started zooming open, while it still is.
        private var openingStartedAt: Date?
        /// How long the zoom-in visibly takes; iOS reports it finished later.
        private static let visibleZoomDuration: TimeInterval = 0.45
        /// Whether a finger is holding the opening.
        private var isOpeningGrabbed = false
        /// The zoom's own dismiss gestures, paused between the zoom-in landing
        /// and iOS reporting the opening finished.
        private var pausedZoomGestures: [UIGestureRecognizer] = []
        /// Whether the current touch began while they were paused. They
        /// can't pick up a touch already under way, so it stays with ours.
        private var touchBeganWhilePaused = false

        init(arrival: ScreenArrival) {
            self.arrival = arrival
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        /// The navigation stack's child that holds this screen.
        private var screen: UIViewController? {
            guard let navigationController else {
                return nil
            }
            return sequence(first: self as UIViewController, next: \.parent)
                .first { $0.parent === navigationController }
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            arrival.isSettled = false
            guard let screen,
                  let coordinator = transitionCoordinator,
                  coordinator.viewController(forKey: .to) === screen else {
                // Not a fresh opening, such as a cancelled swipe back: the
                // screen settles once it is fully back.
                return
            }
            // A screen zooming open takes taps, but it can still be grabbed
            // and swiped away, which cancels the opening instead of popping
            // it. Once grabbed its buttons wait, and if the swipe cancels the
            // opening its touches stop at the moment the finger lets go.
            arrival.isSettled = true
            openingStartedAt = .now
            installSwipeBack(on: screen)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleZoomDuration) { [weak self, weak screen] in
                guard let self, self.openingStartedAt != nil, !self.isOpeningGrabbed else {
                    return
                }
                self.pauseZoomGestures(on: screen)
            }
            coordinator.notifyWhenInteractionChanges { [weak self, weak screen] context in
                MainActor.assumeIsolated {
                    self?.isOpeningGrabbed = context.isInteractive
                    if context.isInteractive {
                        self?.arrival.isSettled = false
                    } else if context.isCancelled {
                        self?.arrival.onDeparture?(.started)
                        self?.stopTouches(on: screen)
                        self?.releaseAfterGlide()
                    } else {
                        self?.settle()
                    }
                }
            }
            coordinator.animate(alongsideTransition: nil) { [weak self, weak screen] context in
                guard context.isCancelled else {
                    return
                }
                MainActor.assumeIsolated {
                    self?.isFinishingCancelledOpening = false
                    self?.stopTouches(on: screen)
                    self?.arrival.onDeparture?(.finished)
                }
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            settle()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            // SwiftUI's screens never report `isMovingFromParent`, but a
            // screen being popped has already left the stack's list.
            guard let navigationController,
                  let screen,
                  !navigationController.viewControllers.contains(where: { $0 === screen }) else {
                return
            }
            arrival.isSettled = false
            swipeBack?.isEnabled = false
            arrival.onDeparture?(.started)

            guard let coordinator = transitionCoordinator else {
                stopTouches(on: screen)
                return
            }
            if coordinator.isInteractive {
                // The finger driving a swipe back stays in charge until it
                // lets go.
                coordinator.notifyWhenInteractionChanges { [weak self, weak screen] context in
                    guard !context.isCancelled else {
                        return
                    }
                    MainActor.assumeIsolated {
                        self?.stopTouches(on: screen)
                    }
                }
            } else {
                stopTouches(on: screen)
            }
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                MainActor.assumeIsolated {
                    if context.isCancelled {
                        self?.settle()
                    } else {
                        self?.arrival.onDeparture?(.finished)
                    }
                }
            }
        }

        private func releaseAfterGlide() {
            isFinishingCancelledOpening = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.isFinishingCancelledOpening else {
                    return
                }
                self.isFinishingCancelledOpening = false
                self.arrival.goBack?()
            }
        }

        private func stopTouches(on screen: UIViewController?) {
            openingStartedAt = nil
            resumeZoomGestures()
            arrival.isSettled = false
            screen?.view.isUserInteractionEnabled = false
            heldScreen = screen
        }

        private func settle() {
            openingStartedAt = nil
            resumeZoomGestures()
            arrival.isSettled = true
            swipeBack?.isEnabled = true
            heldScreen?.view.isUserInteractionEnabled = true
            heldScreen = nil
        }

        // MARK: Swiping back

        private func installSwipeBack(on screen: UIViewController?) {
            guard swipeBack == nil, let screen else {
                return
            }
            let swipeBack = UIPanGestureRecognizer(target: self, action: #selector(swipedBack(_:)))
            swipeBack.delegate = self
            swipeBack.cancelsTouchesInView = true
            screen.view.addGestureRecognizer(swipeBack)
            self.swipeBack = swipeBack
            swipeBackScreen = screen
        }

        /// The zoom's dismiss gestures live on the screen's own view. They
        /// are found by name; if a future iOS names them differently, nothing
        /// is paused and edge swipes stay with the zoom throughout.
        private func pauseZoomGestures(on screen: UIViewController?) {
            guard pausedZoomGestures.isEmpty, let view = screen?.view else {
                return
            }
            pausedZoomGestures = (view.gestureRecognizers ?? []).filter {
                $0.isEnabled && ($0.name?.hasPrefix("com.apple.UIKit.ZoomInteractiveDismiss") ?? false)
            }
            pausedZoomGestures.forEach { $0.isEnabled = false }
        }

        private func resumeZoomGestures() {
            pausedZoomGestures.forEach { $0.isEnabled = true }
            pausedZoomGestures = []
        }

        @objc private func swipedBack(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .began else {
                return
            }
            gesture.isEnabled = false
            // Leaving starts now, even if the pop waits for the zoom-in.
            arrival.isSettled = false
            let remainingZoom = openingStartedAt.map {
                Self.visibleZoomDuration - Date.now.timeIntervalSince($0)
            } ?? 0
            guard remainingZoom > 0 else {
                goBack()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + remainingZoom) { [weak self] in
                self?.goBack()
            }
        }

        private func goBack() {
            guard let screen = swipeBackScreen,
                  screen.navigationController?.topViewController === screen else {
                return
            }
            arrival.goBack?()
        }

        /// A deliberate swipe toward the trailing edge, so scrolling still
        /// scrolls. While the zoom's own swipes are active, those that start
        /// at the leading edge belong to the zoom, which lets them follow the
        /// finger.
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard gesture === swipeBack,
                  let pan = gesture as? UIPanGestureRecognizer,
                  let view = pan.view else {
                return true
            }
            let isRightToLeft = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
            let velocity = pan.velocity(in: view)
            let towardTrailing = isRightToLeft ? -velocity.x : velocity.x
            guard towardTrailing > 150, towardTrailing > abs(velocity.y) else {
                return false
            }
            guard pausedZoomGestures.isEmpty, !touchBeganWhilePaused else {
                return true
            }
            let startX = pan.location(in: view).x - pan.translation(in: view).x
            let fromLeadingEdge = isRightToLeft ? view.bounds.width - startX : startX
            return fromLeadingEdge >= 24
        }

        /// Controls that are dragged sideways, such as the Up Next / All Songs
        /// switcher, keep their drags; a swipe that starts on anything else,
        /// buttons and menus included, still goes back.
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gesture === swipeBack else {
                return true
            }
            touchBeganWhilePaused = !pausedZoomGestures.isEmpty
            let isDraggedSideways = sequence(first: touch.view, next: { $0?.superview })
                .prefix { $0 != nil && $0 !== gesture.view }
                .contains { $0 is UISegmentedControl || $0 is UISlider || $0 is UISwitch }
            return !isDraggedSideways
        }

        /// Scrolling and the zoom's own gestures run alongside the swipe.
        /// Anything else, such as a button being pressed, gives way once the
        /// swipe begins, so lifting the finger never presses it.
        func gestureRecognizer(
            _ gesture: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            guard gesture === swipeBack else {
                return true
            }
            return other.view is UIScrollView || other is UIScreenEdgePanGestureRecognizer
        }
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
private func artworkCornerRadius(for size: CGFloat) -> CGFloat {
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
