import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

// A playlist's page opens out of its cover, follows a finger that swipes it
// back, and shrinks back into the cover. One object owns all of that: the
// stage. A page isn't pushed on the navigation stack, so there is no system
// transition to hand over to or to wait for, and every moment of the motion
// can be grabbed, reversed, or let go:
//
// - A page is a card the stage moves itself, from the first frame of opening
//   to the last frame of closing.
// - A swipe toward the trailing edge, from anywhere on the page, moves the
//   card with the finger. Letting go either sends it into its cover or
//   springs it back, carrying on at the finger's speed.
// - Nothing waits for an animation to finish. A page still opening can be
//   swiped or sent back, and a page on its way back turns round the moment
//   a finger lands on it, or when its playlist is tapped again, from
//   wherever it has got to.
// - Nothing on a page on its way back can be pressed. A finger that lands
//   on it catches the page itself; one that lands beside it reaches the
//   Playlists screen at once.
// - The Playlists screen is never redrawn or laid out again because a page
//   comes or goes: it only dims, in the stage's own layer. A page's motion
//   shares the main thread with nothing else.

// MARK: - Stage

/// The cover a page grows out of and shrinks back into.
enum PageSource: Hashable {
    case playlist(LibraryPlaylist.ID)
    case continueCard
}

/// Shows playlist pages over the Playlists screen.
///
/// Nothing here is published. The Playlists screen is large, and redrawing
/// it as a page set off cost the page's first frames.
@MainActor
final class PlaylistPageStage: ObservableObject {
    /// Whether a page rests over the Playlists screen.
    let cover = PageCover()

    /// How much the Playlists screen dims under a page. It keeps its size
    /// and place: scaling it made the list lay itself out again against
    /// where it was drawn, a jump of its own at the start of every motion.
    fileprivate static let dimming: CGFloat = 0.16

    fileprivate let layout = PageLayout()
    fileprivate weak var controller: PageStageController?
    fileprivate let anchors = NSHashTable<PageSourceAnchorView>.weakObjects()
    /// Sits inside the Playlists screen's navigation stack, to find the
    /// view VoiceOver leaves alone under a page.
    fileprivate weak var browserAnchor: UIView?

    /// Opens a playlist's page out of `source`. Pass the saved queue when
    /// it belongs to this playlist, so its order and live progress carry
    /// over; otherwise a fresh preview order is generated. A page of the
    /// same playlist that is still on its way back comes straight back.
    func open(_ playlist: LibraryPlaylist, savedQueue: PlaylistViewModel? = nil, from source: PageSource) {
        controller?.open(playlist, savedQueue: savedQueue, from: source)
    }

    /// The Playlists screen's navigation view.
    fileprivate var browserView: UIView? {
        guard let browserAnchor else {
            return nil
        }
        let responders = sequence(first: browserAnchor as UIResponder, next: \.next)
        return responders.lazy.compactMap { $0 as? UINavigationController }.first?.view
    }

    /// Where a cover sits, in the stage's coordinates; nil when it isn't
    /// on screen.
    fileprivate func place(of source: PageSource, in stageView: UIView) -> SourcePlace? {
        for anchor in anchors.allObjects where anchor.source == source && anchor.isOnScreen {
            let frame = anchor.convert(anchor.bounds, to: stageView)
            guard frame.width > 1, frame.height > 1, stageView.bounds.intersects(frame) else {
                continue
            }
            return SourcePlace(frame: frame, cornerRadius: anchor.cornerRadius)
        }
        return nil
    }
}

private struct SourcePlace {
    let frame: CGRect
    let cornerRadius: CGFloat
}

/// Whether a page rests over the Playlists screen, for the one view that
/// wants to know: the screen's colour field, which stops drifting while it
/// can't be seen. It changes only while nothing is moving, once a page has
/// come to rest and once the last page has gone, so a page's motion never
/// waits on it.
@MainActor
@Observable
final class PageCover {
    fileprivate(set) var hidesPlaylists = false
}

/// The room a page lays itself out in. A page keeps its own record of the
/// screen's safe area rather than reading UIKit's: UIKit works a view's
/// safe area out from where it sits, and a card shrinking into a cover
/// would otherwise lay its page out again mid-flight.
@MainActor
final class PageLayout: ObservableObject {
    struct Room: Equatable {
        var safeArea = EdgeInsets()
        /// The screen's own bottom inset, without the mini player.
        var deviceBottomInset: CGFloat = 0
        var isCoveredBySheet = false
    }

    @Published private(set) var room = Room()

    func update(_ room: Room) {
        if room != self.room {
            self.room = room
        }
    }

    /// The screen's own insets: the status bar and the home indicator.
    var screenInsets: EdgeInsets {
        EdgeInsets(
            top: room.safeArea.top,
            leading: room.safeArea.leading,
            bottom: min(room.safeArea.bottom, room.deviceBottomInset),
            trailing: room.safeArea.trailing
        )
    }

    /// How much the mini player takes above the home indicator.
    var bottomBarHeight: CGFloat {
        max(0, room.safeArea.bottom - room.deviceBottomInset)
    }
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    /// A playlist page's own coordinate space, which stays put however the
    /// stage moves the page.
    static var playlistPage: NamedCoordinateSpace {
        .named("playlistPage")
    }
}

/// What a page tells the stage about itself, and how it asks to go back.
/// Places are in the page's own coordinate space, `.playlistPage`.
@MainActor
final class PageContext {
    /// Where a control that is dragged sideways sits, so a swipe back never
    /// starts on it.
    var sidewaysDragFrame: CGRect = .null
    /// Where the page's large cover sits, so the card can grow out of and
    /// shrink onto a cover with the two lined up.
    var coverFrame: CGRect = .null {
        didSet {
            if oldValue.isNull, !coverFrame.isNull {
                onCoverPlaced?()
                onCoverPlaced = nil
            }
        }
    }
    fileprivate var onCoverPlaced: (() -> Void)?
    fileprivate var onGoBack: (() -> Void)?

    /// Takes the page back, as its Back button does.
    func goBack() {
        onGoBack?()
    }
}

extension EnvironmentValues {
    /// Opens playlist pages.
    @Entry var pageStage: PlaylistPageStage?
    /// The page a view is on, when it is on one.
    @Entry var playlistPage: PageContext?
}

struct PageServices {
    let playback: MusicPlaybackService
    let pins: PinnedPlaylistStore
    let session: GeneratedQueueSession
    let covers: PlaylistCoverStore
}

// MARK: - SwiftUI

extension View {
    /// Marks the cover a playlist's page grows out of and shrinks back
    /// into.
    func pageSource(_ source: PageSource, cornerRadius: CGFloat) -> some View {
        overlay {
            PageSourceAnchor(source: source, cornerRadius: cornerRadius)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Placed inside the Playlists screen's navigation stack, so the stage
    /// can find the screen a page covers.
    func marksBrowser(for stage: PlaylistPageStage) -> some View {
        background {
            BrowserAnchor(stage: stage)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The layer playlist pages are shown in, over the Playlists screen and
/// under the mini player.
struct PlaylistPageStageLayer: View {
    let stage: PlaylistPageStage
    let deviceBottomInset: CGFloat
    let isCoveredBySheet: Bool

    var body: some View {
        GeometryReader { proxy in
            PlaylistPageStageView(stage: stage)
                .ignoresSafeArea()
                .onChange(
                    of: PageLayout.Room(
                        safeArea: proxy.safeAreaInsets,
                        deviceBottomInset: deviceBottomInset,
                        isCoveredBySheet: isCoveredBySheet
                    ),
                    initial: true
                ) { _, room in
                    stage.layout.update(room)
                }
        }
        // The keyboard is put away as a page opens; its inset isn't the
        // page's. Which touches the layer takes is the stage view's call,
        // touch by touch, so it never waits for this view to be redrawn.
        .ignoresSafeArea(.keyboard)
    }
}

private struct PlaylistPageStageView: UIViewControllerRepresentable {
    let stage: PlaylistPageStage
    @EnvironmentObject private var playbackService: MusicPlaybackService
    @EnvironmentObject private var pinnedPlaylistStore: PinnedPlaylistStore
    @EnvironmentObject private var generatedQueueSession: GeneratedQueueSession
    @EnvironmentObject private var coverStore: PlaylistCoverStore

    func makeUIViewController(context: Context) -> PageStageController {
        PageStageController(
            stage: stage,
            services: PageServices(
                playback: playbackService,
                pins: pinnedPlaylistStore,
                session: generatedQueueSession,
                covers: coverStore
            )
        )
    }

    func updateUIViewController(_ controller: PageStageController, context: Context) {}
}

/// What a page's hosting controller shows: the playlist's screen, laid out
/// in the stage's record of the screen's safe area.
private struct PlaylistPageRoot: View {
    @ObservedObject var layout: PageLayout
    let viewModel: PlaylistViewModel
    let context: PageContext
    let services: PageServices

    var body: some View {
        PlaylistDetailView(viewModel: viewModel)
            .environment(\.playlistPage, context)
            .environment(\.isCoveredBySheet, layout.room.isCoveredBySheet)
            .bottomBarSpace(layout.bottomBarHeight)
            .safeAreaPadding(layout.screenInsets)
            .coordinateSpace(.playlistPage)
            .environmentObject(services.playback)
            .environmentObject(services.pins)
            .environmentObject(services.session)
            .environmentObject(services.covers)
            .tint(.ember)
    }
}

private extension View {
    /// Keeps the page's list clear of the mini player, which floats above
    /// every page. On iOS 26 and later the rows fade beneath it, as they do
    /// on the Playlists screen.
    @ViewBuilder
    func bottomBarSpace(_ height: CGFloat) -> some View {
        if height <= 0 {
            self
        } else if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: height)
                    .allowsHitTesting(false)
            }
        } else {
            safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: height)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct PageSourceAnchor: UIViewRepresentable {
    @Environment(\.pageStage) private var stage
    let source: PageSource
    let cornerRadius: CGFloat

    func makeUIView(context: Context) -> PageSourceAnchorView {
        let view = PageSourceAnchorView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: PageSourceAnchorView, context: Context) {
        view.source = source
        view.cornerRadius = cornerRadius
        stage?.anchors.add(view)
    }
}

fileprivate final class PageSourceAnchorView: UIView {
    var source: PageSource?
    var cornerRadius: CGFloat = 0

    /// In the window, and not in a list row that is waiting to be reused.
    var isOnScreen: Bool {
        window != nil && sequence(first: self as UIView, next: \.superview).allSatisfy { !$0.isHidden }
    }
}

private struct BrowserAnchor: UIViewRepresentable {
    let stage: PlaylistPageStage

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        stage.browserAnchor = view
    }
}

// MARK: - Motion

/// A spring without bounce. The card and the dimming behind it move with
/// the same spring, so they stay in step.
private struct PageSpring {
    /// Roughly how long the motion takes to look finished.
    let response: Double

    /// A page grows out of its cover.
    static let opening = PageSpring(response: 0.38)
    /// A page shrinks into its cover: quicker, as the system's own
    /// transitions leave faster than they arrive.
    static let closing = PageSpring(response: 0.3)
    /// A page that was let go too soon returns to its place.
    static let springingBack = PageSpring(response: 0.36)

    var frequency: Double {
        2 * .pi / response
    }

    var timing: UISpringTimingParameters {
        UISpringTimingParameters(
            mass: 1,
            stiffness: frequency * frequency,
            damping: 2 * frequency,
            initialVelocity: .zero
        )
    }
}

/// Where a page's card is and what it shows of the page.
private struct CardShape {
    /// The card, in the stage's coordinates.
    var frame: CGRect
    var cornerRadius: CGFloat
    /// How large the page is drawn inside the card.
    var pageScale: CGFloat
    /// Where the page's top leading corner sits inside the card.
    var pageOrigin: CGPoint

    func blended(with other: CardShape, by amount: CGFloat) -> CardShape {
        func mix(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
            from + (to - from) * amount
        }
        return CardShape(
            frame: CGRect(
                x: mix(frame.minX, other.frame.minX),
                y: mix(frame.minY, other.frame.minY),
                width: mix(frame.width, other.frame.width),
                height: mix(frame.height, other.frame.height)
            ),
            cornerRadius: mix(cornerRadius, other.cornerRadius),
            pageScale: mix(pageScale, other.pageScale),
            pageOrigin: CGPoint(
                x: mix(pageOrigin.x, other.pageOrigin.x),
                y: mix(pageOrigin.y, other.pageOrigin.y)
            )
        )
    }
}

// MARK: - Controller

/// Holds the pages, decides which one is open, and sorts the touches that
/// land on the stage.
final class PageStageController: UIViewController, UIGestureRecognizerDelegate {
    private let stage: PlaylistPageStage
    private let services: PageServices
    /// The page that takes touches, if any.
    private var openPage: PlaylistPage?
    /// Pages on their way back into their covers.
    private var leavingPages: [PlaylistPage] = []
    /// The page that last went back. Tapping its playlist just after it
    /// lands brings back the same order rather than a fresh shuffle.
    private var lastClosed: (viewModel: PlaylistViewModel, until: Date)?
    private static let lastClosedGrace: TimeInterval = 0.5
    /// Dims the Playlists screen under a page.
    private let dimming = UIView()
    /// One recogniser for the whole stage rather than one per page, so a
    /// finger is followed wherever it lands: on a page, on one that isn't
    /// showing yet, or on one on its way back.
    private let swipe = PageSwipeGestureRecognizer()
    /// The page under the finger the recogniser is watching.
    private weak var touchedPage: PlaylistPage?

    fileprivate init(stage: PlaylistPageStage, services: PageServices) {
        self.stage = stage
        self.services = services
        super.init(nibName: nil, bundle: nil)
        stage.controller = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let view = PageStageView()
        view.takesTouch = { [weak self] point in
            guard let self else {
                return false
            }
            return self.openPage != nil || self.leavingPage(at: point) != nil
        }
        dimming.backgroundColor = .black
        dimming.alpha = 0
        dimming.isUserInteractionEnabled = false
        dimming.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimming.frame = view.bounds
        view.addSubview(dimming)
        swipe.addTarget(self, action: #selector(swiped(_:)))
        swipe.delegate = self
        swipe.touchLanded = { [weak self] point in
            self?.touchLanded(at: point)
        }
        view.addGestureRecognizer(swipe)
        self.view = view
    }

    /// Dims the Playlists screen under an open page, or lights it again,
    /// from wherever it is.
    private func dimPlaylists(_ isDimmed: Bool, spring: PageSpring) {
        let dimming = dimming
        let animator = UIViewPropertyAnimator(duration: 0, timingParameters: spring.timing)
        animator.addAnimations {
            dimming.alpha = isDimmed ? PlaylistPageStage.dimming : 0
        }
        animator.startAnimation()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for page in leavingPages + [openPage].compactMap({ $0 }) {
            page.stageDidResize(to: view.bounds)
        }
    }

    // MARK: Opening and closing

    fileprivate func open(_ playlist: LibraryPlaylist, savedQueue: PlaylistViewModel?, from source: PageSource) {
        guard openPage == nil, isViewLoaded, view.window != nil else {
            return
        }
        view.window?.endEditing(true)

        if let page = leavingPages.last(where: {
            $0.viewModel.playlist.id == playlist.id && (savedQueue == nil || savedQueue === $0.viewModel)
        }) {
            // Still on its way back: the very same page turns round.
            InteractionTrace.note("page reopens on its way back")
            page.source = source
            bringBack(page)
            return
        }

        InteractionTrace.note("page opens")
        let page = PlaylistPage(
            viewModel: savedQueue ?? takeLastClosed(for: playlist) ?? PlaylistDetailView.previewQueue(for: playlist),
            source: source,
            layout: stage.layout,
            services: services,
            bounds: view.bounds
        )
        page.owner = self
        addChild(page.host)
        view.addSubview(page.card)
        page.host.didMove(toParent: self)
        openPage = page
        page.open { [weak self] in
            guard let self else {
                return nil
            }
            return self.stage.place(of: source, in: self.view)
        }
        didOpen(page)
    }

    /// Turns a page that was on its way back around, from where it has got
    /// to.
    private func bringBack(_ page: PlaylistPage) {
        leavingPages.removeAll { $0 === page }
        view.bringSubviewToFront(page.card)
        openPage = page
        page.reopen()
        didOpen(page)
    }

    private func didOpen(_ page: PlaylistPage) {
        dimPlaylists(true, spring: .opening)
        // VoiceOver leaves the screen under the page alone. Set on the
        // view itself: nothing of the Playlists screen is redrawn for it.
        stage.browserView?.accessibilityElementsHidden = true
        UIAccessibility.post(notification: .screenChanged, argument: page.card)
    }

    /// Sends the open page back into its cover, setting off at `velocity`.
    fileprivate func close(_ page: PlaylistPage, velocity: CGVector) {
        guard openPage === page else {
            return
        }
        InteractionTrace.note("page goes back")
        openPage = nil
        leavingPages.append(page)
        lastClosed = (page.viewModel, .distantFuture)
        let place = stage.place(of: page.source, in: view)
            ?? stage.place(of: .playlist(page.viewModel.playlist.id), in: view)
        page.close(to: place, velocity: velocity)
        dimPlaylists(false, spring: .closing)
        stage.browserView?.accessibilityElementsHidden = false
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    /// The open page has come to rest, so the Playlists screen can't be
    /// seen.
    fileprivate func didSettle(_ page: PlaylistPage) {
        if openPage === page, !stage.cover.hidesPlaylists {
            stage.cover.hidesPlaylists = true
        }
    }

    fileprivate func didClose(_ page: PlaylistPage) {
        guard let index = leavingPages.firstIndex(where: { $0 === page }) else {
            return
        }
        InteractionTrace.note("page gone")
        leavingPages.remove(at: index)
        page.host.willMove(toParent: nil)
        page.card.removeFromSuperview()
        page.host.removeFromParent()
        if lastClosed?.viewModel === page.viewModel {
            lastClosed?.until = .now.addingTimeInterval(Self.lastClosedGrace)
        }
        if openPage == nil, leavingPages.isEmpty, stage.cover.hidesPlaylists {
            stage.cover.hidesPlaylists = false
        }
    }

    private func takeLastClosed(for playlist: LibraryPlaylist) -> PlaylistViewModel? {
        defer {
            lastClosed = nil
        }
        guard let lastClosed, lastClosed.viewModel.playlist.id == playlist.id, lastClosed.until > .now else {
            return nil
        }
        return lastClosed.viewModel
    }

    // MARK: Touches

    /// The page on its way back that is showing under `point`, if any.
    private func leavingPage(at point: CGPoint) -> PlaylistPage? {
        leavingPages.last { $0.canBeCaught(at: point) }
    }

    /// A finger has landed on the stage, at `point` in the window. On the
    /// open page it may turn out to be a swipe back. On a page on its way
    /// back it catches the page there and then, as a finger stops a list
    /// that is still gliding: the page turns round, and goes with the
    /// finger if it moves.
    private func touchLanded(at point: CGPoint) -> PageSwipeGestureRecognizer.Landing? {
        if let openPage {
            touchedPage = openPage
            return .onOpenPage
        }
        guard let page = leavingPage(at: view.convert(point, from: nil)) else {
            touchedPage = nil
            return nil
        }
        InteractionTrace.note("page caught on its way back")
        bringBack(page)
        touchedPage = page
        return .onCaughtPage
    }

    @objc private func swiped(_ gesture: PageSwipeGestureRecognizer) {
        guard let page = touchedPage else {
            return
        }
        switch gesture.state {
        case .began:
            // A press or a scroll the finger started ends here.
            gesture.cancelOtherGestures()
            page.beginDrag(at: view.convert(gesture.touchDownLocation, from: nil))
            page.follow(translation: gesture.translation, distance: gesture.distance)
        case .changed:
            page.follow(translation: gesture.translation, distance: gesture.distance)
        case .ended:
            page.follow(translation: gesture.translation, distance: gesture.distance)
            let goesBack = PageSwipe.goesBack(
                distance: gesture.distance,
                speed: gesture.speed,
                width: view.bounds.width
            )
            InteractionTrace.note(
                "swipe back lifted at \(Int(gesture.distance)) pt, \(Int(gesture.speed)) pt/s: \(goesBack ? "goes back" : "stays")"
            )
            page.endDrag(goingBack: goesBack, velocity: gesture.velocity)
        case .cancelled:
            InteractionTrace.note("swipe back interrupted: stays")
            page.endDrag(goingBack: false, velocity: .zero)
        default:
            break
        }
    }

    // MARK: UIGestureRecognizerDelegate

    /// The open page can be swiped whether it has settled or not.
    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard let touchedPage else {
            return false
        }
        return touchedPage === openPage && touchedPage.canBeDragged
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let openPage {
            return openPage.letsSwipeStart(on: touch)
        }
        return leavingPage(at: touch.location(in: view)) != nil
    }

    /// Everything on the page runs alongside the swipe until it begins, so
    /// a button pressed or a list stopped as the finger lands doesn't end
    /// it; once it begins, it cancels them.
    func gestureRecognizer(
        _ gesture: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

/// The stage's own view. A touch on a page's content goes to that content.
/// Any other touch is the stage's while a page is open, such as one beside
/// a card that a finger is holding or on a page that isn't showing yet, and
/// when it lands on a page on its way back; the rest fall through to the
/// Playlists screen.
private final class PageStageView: UIView {
    var takesTouch: (CGPoint) -> Bool = { _ in false }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else {
            return nil
        }
        guard hit === self else {
            return hit
        }
        return takesTouch(point) ? self : nil
    }
}

// MARK: - Page

/// One playlist page: its card, its content, and its motion.
///
/// The card clips the page and is the only thing that moves. The page inside
/// keeps its full size and is only ever scaled and shifted, so it is never
/// laid out again mid-flight. Springs run in the render server and stay
/// smooth while the app is busy; each one starts from wherever the card is
/// showing at that moment, which is what lets any motion be interrupted.
@MainActor
private final class PlaylistPage: NSObject {
    enum Phase {
        case opening
        case open
        case dragging
        case springingBack
        case closing
    }

    private struct Drag {
        /// Where the finger landed, in the stage's coordinates.
        let grip: CGPoint
        /// Where the card was when the swipe took it.
        let origin: CardShape
        let originAlpha: CGFloat
        let startedAt: CFTimeInterval
        /// How long the card takes to come under the finger.
        let catchUp: CFTimeInterval
        var translation = CGPoint.zero
        var distance: CGFloat = 0
    }

    /// The card's corners while it is away from its place. At rest the
    /// screen's own corners are rounder, so these never show.
    private static let cardCornerRadius: CGFloat = 44
    /// The fastest a card sets off when let go, in points per second.
    private static let fastestCarriedSpeed: CGFloat = 2600

    let viewModel: PlaylistViewModel
    var source: PageSource
    let card = PageCardView()
    let host: UIHostingController<PlaylistPageRoot>
    weak var owner: PageStageController?

    private let context: PageContext
    private var phase = Phase.opening
    /// The page's place at rest: the whole stage.
    private var bounds: CGRect
    private var mover: UIViewPropertyAnimator?
    private var fader: UIViewPropertyAnimator?
    /// Counts motions, so a finished animation knows whether it is still
    /// the latest one.
    private var motion = 0
    private var drag: Drag?
    private var catchUpLink: CADisplayLink?
    /// Set while a new page waits for its first frame to be drawn before
    /// it sets off.
    private var isWaitingToOpen = false
    /// Where a new page opens from, until it has taken its place there.
    private var placeToOpenFrom: (() -> SourcePlace?)?
    /// Whether the page, on its way back, is shrinking into a cover rather
    /// than fading where it is.
    private var shrinksIntoCover = false

    init(
        viewModel: PlaylistViewModel,
        source: PageSource,
        layout: PageLayout,
        services: PageServices,
        bounds: CGRect
    ) {
        let context = PageContext()
        self.viewModel = viewModel
        self.source = source
        self.context = context
        self.bounds = bounds
        host = UIHostingController(
            rootView: PlaylistPageRoot(layout: layout, viewModel: viewModel, context: context, services: services)
        )
        super.init()

        // The page lays out in the stage's record of the safe area, never
        // UIKit's, which changes as the card moves.
        host.safeAreaRegions = []
        host.view.backgroundColor = .systemBackground
        host.view.autoresizingMask = []
        host.view.bounds = CGRect(origin: .zero, size: bounds.size)
        card.autoresizesSubviews = false
        card.layer.cornerCurve = .continuous
        card.accessibilityViewIsModal = true
        card.addSubview(host.view)
        card.onEscape = { [weak self] in
            self?.goBack()
        }
        context.onGoBack = { [weak self] in
            self?.goBack()
        }
        apply(restShape)
    }

    // MARK: Shapes

    private var restShape: CardShape {
        CardShape(frame: bounds, cornerRadius: Self.cardCornerRadius, pageScale: 1, pageOrigin: .zero)
    }

    /// The card as a cover. When the page's own large cover is in view, the
    /// card shows exactly that, at the size of the cover it lands on, so the
    /// two line up; a scrolled page shows its top instead.
    private func coverShape(at place: SourcePlace) -> CardShape {
        let cover = context.coverFrame
        if !cover.isNull, cover.width > 1, bounds.insetBy(dx: -1, dy: -1).contains(cover) {
            let scale = place.frame.width / cover.width
            return CardShape(
                frame: place.frame,
                cornerRadius: place.cornerRadius,
                pageScale: scale,
                pageOrigin: CGPoint(x: -cover.minX * scale, y: -cover.minY * scale)
            )
        }
        return CardShape(
            frame: place.frame,
            cornerRadius: place.cornerRadius,
            pageScale: place.frame.width / max(bounds.width, 1),
            pageOrigin: .zero
        )
    }

    private func apply(_ shape: CardShape) {
        card.bounds = CGRect(origin: .zero, size: shape.frame.size)
        card.center = CGPoint(x: shape.frame.midX, y: shape.frame.midY)
        card.layer.cornerRadius = shape.cornerRadius
        host.view.transform = CGAffineTransform(scaleX: shape.pageScale, y: shape.pageScale)
        host.view.center = CGPoint(
            x: shape.pageOrigin.x + bounds.width * shape.pageScale / 2,
            y: shape.pageOrigin.y + bounds.height * shape.pageScale / 2
        )
    }

    /// The card as it is being shown this instant, mid-animation or not.
    private var shownShape: CardShape {
        shape(of: card.layer.presentation() ?? card.layer, page: host.view.layer.presentation() ?? host.view.layer)
    }

    private func shape(of card: CALayer, page: CALayer) -> CardShape {
        let size = card.bounds.size
        let scale = page.affineTransform().a
        return CardShape(
            frame: CGRect(
                x: card.position.x - size.width / 2,
                y: card.position.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            cornerRadius: card.cornerRadius,
            pageScale: scale,
            pageOrigin: CGPoint(
                x: page.position.x - bounds.width * scale / 2,
                y: page.position.y - bounds.height * scale / 2
            )
        )
    }

    // MARK: Motion

    /// Stops whatever is moving the card and leaves it exactly where it is
    /// showing, ready for the next motion to start from there.
    private func holdInPlace() {
        if isWaitingToOpen {
            // Not drawn yet: it is where it would have set off from.
            isWaitingToOpen = false
            takeStartingShape()
        } else {
            let shape = shownShape
            let alpha = CGFloat((card.layer.presentation() ?? card.layer).opacity)
            mover?.stopAnimation(true)
            fader?.stopAnimation(true)
            card.layer.removeAllAnimations()
            host.view.layer.removeAllAnimations()
            apply(shape)
            card.alpha = alpha
        }
        mover = nil
        fader = nil
        stopCatchingUp()
        motion += 1
    }

    /// The card clips to its corners only while it is away from its place.
    private func clipToCorners() {
        card.layer.masksToBounds = true
        if card.layer.cornerRadius == 0 {
            card.layer.cornerRadius = Self.cardCornerRadius
        }
    }

    private func move(
        to shape: CardShape,
        spring: PageSpring,
        velocity: CGVector = .zero,
        completion: (() -> Void)? = nil
    ) {
        let motion = motion
        let mover = UIViewPropertyAnimator(duration: 0, timingParameters: spring.timing)
        mover.addAnimations {
            self.apply(shape)
        }
        mover.addCompletion { [weak self] position in
            guard let self, position == .end, self.motion == motion else {
                return
            }
            completion?()
        }
        mover.startAnimation()
        self.mover = mover
        carry(velocity, with: spring)
    }

    /// Sets the card off at the speed the finger let go with. The spring
    /// itself starts from a standstill; this adds exactly the motion the
    /// same spring gives a push at that speed, so together they are one
    /// spring set off at the finger's speed, in both directions at once.
    private func carry(_ velocity: CGVector, with spring: PageSpring) {
        let speed = hypot(velocity.dx, velocity.dy)
        guard speed > 20 else {
            return
        }
        let limit = min(1, Self.fastestCarriedSpeed / speed)
        let frequency = spring.frequency
        let duration = 10 / frequency
        let steps = 60
        let push = CAKeyframeAnimation(keyPath: "position")
        push.isAdditive = true
        push.duration = duration
        push.calculationMode = .linear
        push.values = (0...steps).map { step in
            let time = duration * Double(step) / Double(steps)
            let travel = time * exp(-frequency * time)
            return NSValue(cgPoint: CGPoint(x: velocity.dx * limit * travel, y: velocity.dy * limit * travel))
        }
        card.layer.add(push, forKey: "carriedSpeed")
    }

    private func fade(
        to alpha: CGFloat,
        duration: TimeInterval,
        delay: TimeInterval = 0,
        completion: (() -> Void)? = nil
    ) {
        let motion = motion
        fader?.stopAnimation(true)
        let fader = UIViewPropertyAnimator(duration: duration, curve: alpha > 0 ? .easeOut : .easeIn) {
            self.card.alpha = alpha
        }
        fader.addCompletion { [weak self] position in
            guard let self, position == .end, self.motion == motion else {
                return
            }
            completion?()
        }
        fader.startAnimation(afterDelay: delay)
        self.fader = fader
    }

    /// At rest: in place, taking touches, with nothing left to clip.
    private func settle() {
        phase = .open
        apply(restShape)
        card.alpha = 1
        card.layer.cornerRadius = 0
        card.layer.masksToBounds = false
        owner?.didSettle(self)
    }

    // MARK: Opening and closing

    /// Grows the page out of the cover at `place`. With Reduce Motion it
    /// fades in where it is.
    ///
    /// Building a page takes the main thread for a few frames, and a spring
    /// started before that work is over would be drawn from part-way
    /// through. So the card first sits on its cover, showing the page's own
    /// cover at that size, which looks as the screen did; the spring starts
    /// once that frame has been handed over. A finger can take the page
    /// from the first moment either way: the stage keeps the touches of a
    /// card that isn't showing yet.
    func open(from place: @escaping () -> SourcePlace?) {
        phase = .opening
        card.alpha = 0
        isWaitingToOpen = true
        placeToOpenFrom = place
        // Lays the page out, which is when it says where its cover sits.
        host.view.layoutIfNeeded()
        if !context.coverFrame.isNull {
            takeStartingShape()
        }
        DispatchQueue.main.async { [weak self] in
            self?.beginOpening()
        }
    }

    /// Puts a new page's card where it opens from: on its cover, or, with
    /// no cover on screen, a little small around its own middle.
    private func takeStartingShape() {
        guard let place = placeToOpenFrom else {
            return
        }
        placeToOpenFrom = nil
        clipToCorners()
        guard !UIAccessibility.isReduceMotionEnabled else {
            apply(restShape)
            return
        }
        if let place = place() {
            apply(coverShape(at: place))
            card.alpha = 1
        } else {
            apply(shrunkShape(of: restShape, to: 0.86))
        }
    }

    private func beginOpening() {
        guard isWaitingToOpen, phase == .opening else {
            return
        }
        isWaitingToOpen = false
        takeStartingShape()
        motion += 1
        growOpen()
    }

    /// Takes the card to its place from wherever it is.
    private func growOpen() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            apply(restShape)
            fade(to: 1, duration: 0.2) { [weak self] in
                self?.settle()
            }
            return
        }
        move(to: restShape, spring: .opening) { [weak self] in
            self?.settle()
        }
        if card.alpha < 1 {
            fade(to: 1, duration: 0.1)
        }
    }

    /// Turns a page that was on its way back around, from where it has got
    /// to.
    func reopen() {
        holdInPlace()
        clipToCorners()
        phase = .opening
        card.isUserInteractionEnabled = true
        card.accessibilityElementsHidden = false
        growOpen()
    }

    /// Shrinks the page into the cover at `place`, from wherever it is and
    /// setting off at `velocity`. From this moment nothing on it can be
    /// pressed. Without a cover on screen, or with Reduce Motion, it fades
    /// out.
    func close(to place: SourcePlace?, velocity: CGVector) {
        drag = nil
        holdInPlace()
        clipToCorners()
        phase = .closing
        card.isUserInteractionEnabled = false
        card.accessibilityElementsHidden = true
        shrinksIntoCover = false
        let finish: () -> Void = { [weak self] in
            guard let self else {
                return
            }
            self.owner?.didClose(self)
        }
        if UIAccessibility.isReduceMotionEnabled {
            fade(to: 0, duration: 0.2, completion: finish)
        } else if let place {
            shrinksIntoCover = true
            move(to: coverShape(at: place), spring: .closing, velocity: velocity)
            // The card is the cover's own size as it fades, so the cover
            // beneath seems to have been there all along.
            fade(to: 0, duration: 0.12, delay: 0.16, completion: finish)
        } else {
            move(to: shrunkShape(of: shownShape, to: 0.86), spring: .closing, velocity: velocity)
            fade(to: 0, duration: 0.18, completion: finish)
        }
    }

    /// Whether a finger landing at `point`, in the stage's coordinates,
    /// lands on this page as it shrinks into its cover. A page that is
    /// fading out, where it is or over its cover at the end, is already as
    /// good as gone: touches there are the Playlists screen's.
    func canBeCaught(at point: CGPoint) -> Bool {
        guard phase == .closing, shrinksIntoCover else {
            return false
        }
        let shown = card.layer.presentation() ?? card.layer
        return shown.opacity > 0.5 && shown.frame.contains(point)
    }

    private func shrunkShape(of shape: CardShape, to scale: CGFloat) -> CardShape {
        var shrunk = shape
        shrunk.frame = shape.frame.insetBy(
            dx: shape.frame.width * (1 - scale) / 2,
            dy: shape.frame.height * (1 - scale) / 2
        )
        shrunk.pageScale = shape.pageScale * scale
        shrunk.pageOrigin = CGPoint(x: shape.pageOrigin.x * scale, y: shape.pageOrigin.y * scale)
        return shrunk
    }

    private func goBack() {
        owner?.close(self, velocity: .zero)
    }

    func stageDidResize(to bounds: CGRect) {
        guard bounds != self.bounds else {
            return
        }
        self.bounds = bounds
        host.view.bounds = CGRect(origin: .zero, size: bounds.size)
        if phase == .open {
            settle()
        }
    }

    // MARK: Swiping back

    /// A page can be swiped whenever it is the open one, settled or not.
    var canBeDragged: Bool {
        phase != .closing && phase != .dragging
    }

    /// Controls that are dragged sideways, such as the Up Next / All Songs
    /// switcher, keep their drags; a swipe that starts on anything else,
    /// buttons and menus included, can still go back.
    func letsSwipeStart(on touch: UITouch) -> Bool {
        guard phase != .closing else {
            return false
        }
        // A touch on the stage itself, such as one on a page that isn't
        // showing yet, has nothing under it to keep the drag.
        guard let touched = touch.view, touched.isDescendant(of: card) else {
            return true
        }
        if context.sidewaysDragFrame.contains(touch.location(in: host.view)) {
            return false
        }
        let isDraggedSideways = sequence(first: touched, next: \.superview)
            .prefix { $0 !== card }
            .contains { $0 is UISegmentedControl || $0 is UISlider || $0 is UISwitch }
        return !isDraggedSideways
    }

    /// A finger that landed at `grip`, in the stage's coordinates, takes
    /// the card from wherever it is.
    func beginDrag(at grip: CGPoint) {
        InteractionTrace.note("swipe back takes the page" + (phase == .open ? "" : " mid-flight"))
        holdInPlace()
        clipToCorners()
        phase = .dragging
        let origin = shape(of: card.layer, page: host.view.layer)
        drag = Drag(
            grip: grip,
            origin: origin,
            originAlpha: card.alpha,
            startedAt: CACurrentMediaTime(),
            catchUp: PageSwipe.catchUpDuration(shownWidth: origin.frame.width, width: bounds.width)
        )
        let link = CADisplayLink(target: self, selector: #selector(catchUp))
        link.add(to: .main, forMode: .common)
        catchUpLink = link
    }

    func follow(translation: CGPoint, distance: CGFloat) {
        drag?.translation = translation
        drag?.distance = distance
        placeCardUnderFinger()
    }

    @objc private func catchUp() {
        placeCardUnderFinger()
    }

    private func stopCatchingUp() {
        catchUpLink?.invalidate()
        catchUpLink = nil
    }

    private func placeCardUnderFinger() {
        guard phase == .dragging, let drag else {
            stopCatchingUp()
            return
        }
        let frame = PageSwipe.cardFrame(
            page: bounds,
            grip: drag.grip,
            translation: drag.translation,
            distance: drag.distance
        )
        let underFinger = CardShape(
            frame: frame,
            cornerRadius: Self.cardCornerRadius,
            pageScale: frame.width / max(bounds.width, 1),
            pageOrigin: .zero
        )
        let elapsed = (CACurrentMediaTime() - drag.startedAt) / drag.catchUp
        guard elapsed < 1 else {
            stopCatchingUp()
            apply(underFinger)
            card.alpha = 1
            return
        }
        // A swipe is sorted a few points after the finger sets off, and a
        // card can be taken mid-flight; it comes under the finger easing
        // out, closing most of the gap at once, rather than jumping to it.
        let amount = 1 - pow(1 - CGFloat(max(elapsed, 0)), 3)
        apply(drag.origin.blended(with: underFinger, by: amount))
        card.alpha = drag.originAlpha + (1 - drag.originAlpha) * amount
    }

    func endDrag(goingBack: Bool, velocity: CGVector) {
        guard phase == .dragging else {
            return
        }
        drag = nil
        stopCatchingUp()
        if goingBack, let owner {
            owner.close(self, velocity: velocity)
        } else {
            springBack(velocity: velocity)
        }
    }

    private func springBack(velocity: CGVector) {
        holdInPlace()
        phase = .springingBack
        move(to: restShape, spring: .springingBack, velocity: velocity) { [weak self] in
            self?.settle()
        }
        if card.alpha < 1 {
            fade(to: 1, duration: 0.1)
        }
    }
}

/// A page's card: it clips the page, and answers VoiceOver's escape gesture
/// by going back.
private final class PageCardView: UIView {
    var onEscape: (() -> Void)?

    override func accessibilityPerformEscape() -> Bool {
        guard let onEscape else {
            return false
        }
        onEscape()
        return true
    }
}

// MARK: - Swipe

/// Follows a finger on the stage.
///
/// On the open page it takes a swipe back from anywhere: it begins once the
/// finger has gone a few points toward the trailing edge holding roughly
/// level, whether it drifts up or down, and ends when the finger lifts. It
/// fails for a tap, a scroll, and a swipe toward the leading edge. A finger
/// that rests first is sorted once it sets off. On a page caught on its way
/// back it begins whichever way the finger sets off.
private final class PageSwipeGestureRecognizer: UIGestureRecognizer {
    /// What a finger landed on.
    enum Landing {
        case onOpenPage
        /// A page that was on its way back, which the finger now holds.
        case onCaughtPage
    }

    /// Asked as a finger lands, with where it landed in window
    /// coordinates; nil when it landed on nothing of the stage's.
    var touchLanded: ((CGPoint) -> Landing?)?

    /// Where the finger landed, in window coordinates: the page moves with
    /// the finger, so the page's own coordinates would move under it.
    private(set) var touchDownLocation: CGPoint = .zero
    private var landing = Landing.onOpenPage
    private var samples: [(location: CGPoint, time: TimeInterval)] = []
    private var liftedAt: TimeInterval?
    /// The touch's other gestures, to cancel once this begins.
    private var otherGestures: [UIGestureRecognizer] = []

    /// The finger's speed is measured over its moves in this last moment.
    private static let speedWindow: TimeInterval = 0.06
    /// A finger that stays still this long before lifting has stopped.
    private static let restingTime: TimeInterval = 0.08

    /// How far the finger has moved since it landed.
    var translation: CGPoint {
        guard let last = samples.last else {
            return .zero
        }
        return CGPoint(x: last.location.x - touchDownLocation.x, y: last.location.y - touchDownLocation.y)
    }

    /// How far the finger has gone toward the trailing edge.
    var distance: CGFloat {
        translation.x * towardTrailing
    }

    /// How fast the finger was last moving, in points per second, over its
    /// moves in the last moment, or since the move before when there were
    /// none. A finger that rested before it lifted isn't moving.
    var velocity: CGVector {
        guard let last = samples.last else {
            return .zero
        }
        if let liftedAt, liftedAt - last.time > Self.restingTime {
            return .zero
        }
        guard let first = samples.first(where: { $0.time < last.time && last.time - $0.time <= Self.speedWindow })
                ?? samples.last(where: { $0.time < last.time }) else {
            return .zero
        }
        let elapsed = last.time - first.time
        return CGVector(
            dx: (last.location.x - first.location.x) / elapsed,
            dy: (last.location.y - first.location.y) / elapsed
        )
    }

    /// How fast the finger was last moving toward the trailing edge.
    var speed: CGFloat {
        velocity.dx * towardTrailing
    }

    private var towardTrailing: CGFloat {
        view?.effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        // One finger only; a second one ends the swipe.
        guard samples.isEmpty, touches.count == 1, let touch = touches.first else {
            interrupt()
            return
        }
        touchDownLocation = touch.location(in: nil)
        guard let landing = touchLanded?(touchDownLocation) else {
            state = .failed
            return
        }
        self.landing = landing
        samples = [(touchDownLocation, touch.timestamp)]
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first else {
            return
        }
        record(touch, with: event)

        switch state {
        case .began, .changed:
            state = .changed
            return
        case .possible:
            break
        default:
            return
        }
        switch PageSwipe.sorting(distance: distance, rise: translation.y, holdsPage: landing == .onCaughtPage) {
        case .undecided:
            return
        case .other:
            InteractionTrace.note("swipe back leaves it: \(distance > 0 ? "a scroll" : "not toward the trailing edge")")
            state = .failed
        case .swipeBack:
            InteractionTrace.note("swipe back sorted at \(Int(distance)) pt, \(Int(speed)) pt/s")
            otherGestures = (touch.gestureRecognizers ?? []).filter { other in
                guard let view, let otherView = other.view else {
                    return false
                }
                return other !== self && otherView.isDescendant(of: view)
            }
            state = .began
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        if let touch = touches.first {
            record(touch, with: event)
            liftedAt = touch.timestamp
        }
        switch state {
        case .possible:
            state = .failed
        case .began, .changed:
            state = .ended
        default:
            break
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        interrupt()
    }

    /// Notes where the finger has been. While the app is busy its moves
    /// arrive together, each with its own time, so the speed stays true. A
    /// finger that lifts where it last moved adds nothing, so a flick keeps
    /// its speed.
    private func record(_ touch: UITouch, with event: UIEvent) {
        for move in event.coalescedTouches(for: touch) ?? [touch] {
            let location = move.location(in: nil)
            if location != samples.last?.location {
                samples.append((location, move.timestamp))
            }
        }
        // The last moment's moves, and the one before them.
        if let newest = samples.last?.time,
           let stale = samples.lastIndex(where: { newest - $0.time > Self.speedWindow }) {
            samples.removeFirst(stale)
        }
    }

    override func reset() {
        super.reset()
        samples = []
        liftedAt = nil
        otherGestures = []
        landing = .onOpenPage
    }

    /// Ends whatever else the finger started, such as a button's press or
    /// the list's scrolling. Switching a gesture off and on again cancels
    /// it.
    func cancelOtherGestures() {
        for gesture in otherGestures where gesture.isEnabled {
            gesture.isEnabled = false
            gesture.isEnabled = true
        }
        otherGestures = []
    }

    private func interrupt() {
        switch state {
        case .possible:
            state = .failed
        case .began, .changed:
            state = .cancelled
        default:
            break
        }
    }
}
