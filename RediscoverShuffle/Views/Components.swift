import MediaPlayer
import MusicKit
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

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
    /// Marks the cover a zoom transition grows from. Zoom transitions need
    /// iOS 18; earlier versions keep the standard push.
    ///
    /// The zoom fades its source, scaled up to the whole page's width, over
    /// the page as it grows and shrinks, so a cover as the source showed a
    /// blown-up second copy of itself, text and all, over the page's own
    /// artwork. The source is a clear pane laid over the cover instead: the
    /// page still grows out of the cover and shrinks back into it, with
    /// nothing extra drawn over it, and the cover itself stays in place.
    @ViewBuilder
    func zoomSource(id: some Hashable, in namespace: Namespace.ID, cornerRadius: CGFloat) -> some View {
        if #available(iOS 18.0, *) {
            overlay {
                // Nearly clear rather than clear, which draws nothing for
                // the zoom to take its frame from.
                Color.black.opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .matchedTransitionSource(id: id, in: namespace) { source in
                        source.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    }
            }
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
    /// Takes the screen back, as its Back button does; `animated` is false
    /// when iOS is already animating it away and SwiftUI only needs telling.
    var goBack: ((_ animated: Bool) -> Void)?
    /// Where a control drawn in SwiftUI that is dragged sideways sits, in
    /// window coordinates, so a swipe back never starts on it.
    var sidewaysDragFrame: CGRect = .null

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
/// Swipes back follow the finger, as in Music and Photos, and letting go
/// decides whether the screen goes back. The zoom's own swipes do that from
/// the leading edge, and from anywhere while a screen is opening and, on
/// iOS 26, once it has opened. But the zoom's swipe from the middle only
/// takes a swipe that sets off level or slightly downward; one that drifts
/// up even a little, as a thumb sweeping right often does, it passes on,
/// and the navigation stack's own content swipe never takes touches on a
/// zoomed screen.
///
/// So iOS's swipes sort each touch first, and the app's swipe takes the
/// swipes back they pass on and moves the page itself, the way the zoom
/// does: the page shrinks into a card that follows the finger over the
/// Playlists screen, which sits back and dims just as the zoom sets it.
/// Letting go past about a third of the width, or with a flick toward the
/// trailing edge, sends it back, and the zoom carries on from the card into
/// the cover; otherwise it springs back. While a screen is still zooming
/// open, and before iOS 18, which has no zoom, the page can't be moved, so
/// such a swipe goes back on lift instead. A finger that rests, a scroll,
/// or a swipe toward the leading edge it leaves alone. A swipe it takes
/// cancels the press or scroll the finger started, as iOS's swipes do, so a
/// swipe never presses a button it started on.
///
/// A swipe that cancels an opening glides the screen back to its row in
/// about a quarter of a second, but iOS only reports it gone about a second
/// later, and until then SwiftUI still counts it as open and ignores taps
/// that would open it again. So as soon as a finger lands anywhere, or once
/// iOS has finished, SwiftUI is told the screen has gone, without an
/// animation of its own. It isn't told on a timer: telling it while iOS was
/// still finishing the glide started a second transition, which redrew the
/// Playlists screen's bar and its soft top edge for a few frames.
///
/// The app goes back through SwiftUI, as the Back button does. Popping in
/// UIKit directly left SwiftUI counting the screen as open until the zoom
/// back ended, so tapping the same playlist couldn't catch it. A pop during
/// the zoom-in makes iOS snap the screen fully open first, so such a flick
/// waits until the zoom-in has visibly landed.
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
        /// Takes the swipes back from the middle of the screen that iOS's
        /// swipes pass on.
        private var swipeBack: SwipeBackGestureRecognizer?
        private weak var swipeBackScreen: UIViewController?
        /// Moves the page with the finger during one of those swipes.
        private var follower: SwipeFollower?
        /// An opening that a swipe cancelled and iOS hasn't finished yet.
        private var isFinishingCancelledOpening = false
        /// When the screen started zooming open, while it still is.
        private var openingStartedAt: Date?
        /// How long the zoom-in visibly takes; iOS reports it finished later.
        private static let visibleZoomDuration: TimeInterval = 0.45
        /// Swipes from this close to the leading edge belong to iOS.
        private static let leadingEdgeWidth: CGFloat = 24
        /// How long a page the finger moved waits for the zoom to take it.
        private static let handOverTimeout: TimeInterval = 0.5
        /// Lets go of a cancelled opening the moment a finger lands.
        private var touchDownWatcher: TouchDownWatcher?

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
            InteractionTrace.note("screen opens")
            coordinator.notifyWhenInteractionChanges { [weak self, weak screen] context in
                MainActor.assumeIsolated {
                    InteractionTrace.note(
                        context.isInteractive
                            ? "opening grabbed by a swipe"
                            : context.isCancelled ? "finger let go: opening cancelled" : "finger let go: opening continues"
                    )
                    if context.isInteractive {
                        // The zoom's own swipe has the screen; the app's
                        // stays out of it until the screen settles.
                        self?.arrival.isSettled = false
                        self?.swipeBack?.isEnabled = false
                    } else if context.isCancelled {
                        self?.arrival.onDeparture?(.started)
                        self?.stopTouches(on: screen)
                        self?.releaseOnNextTouch()
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
                    // iOS has finished, so if no finger landed meanwhile,
                    // SwiftUI can now be told without disturbing anything.
                    self?.releaseCancelledOpening()
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
            if let follower {
                // The zoom takes the page from where the finger left it.
                self.follower = nil
                follower.handOver(to: transitionCoordinator)
            }

            guard let coordinator = transitionCoordinator else {
                InteractionTrace.note("screen leaves without animating")
                stopTouches(on: screen)
                return
            }
            InteractionTrace.note(coordinator.isInteractive ? "screen leaves, following the finger" : "screen leaves")
            if coordinator.isInteractive {
                // The finger driving a swipe back stays in charge until it
                // lets go.
                coordinator.notifyWhenInteractionChanges { [weak self, weak screen] context in
                    MainActor.assumeIsolated {
                        InteractionTrace.note(context.isCancelled ? "finger let go: screen springs back" : "finger let go: screen goes")
                        guard !context.isCancelled else {
                            return
                        }
                        self?.stopTouches(on: screen)
                    }
                }
            } else {
                stopTouches(on: screen)
            }
            fadeTitle(of: screen, alongside: coordinator)
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                MainActor.assumeIsolated {
                    InteractionTrace.note(context.isCancelled ? "screen stayed" : "screen gone")
                    if context.isCancelled {
                        self?.settle()
                    } else {
                        self?.arrival.onDeparture?(.finished)
                    }
                }
            }
        }

        /// The bar's title, drawn by SwiftUI, fades out more slowly than the
        /// bar's buttons as a screen goes back, and stayed faintly over the
        /// Playlists screen after the page had landed. It fades with the
        /// buttons instead, early in the transition, following the finger
        /// during a swipe, and comes back if the swipe is cancelled.
        private func fadeTitle(of screen: UIViewController, alongside coordinator: UIViewControllerTransitionCoordinator) {
            guard let title = screen.navigationItem.titleView else {
                return
            }
            coordinator.animate(alongsideTransition: { context in
                guard context.isInteractive else {
                    // The zoom's spring would drop it within a frame; this
                    // matches the buttons' fade.
                    UIView.animate(
                        withDuration: 0.12,
                        delay: 0,
                        options: [.overrideInheritedDuration, .overrideInheritedCurve, .curveEaseOut]
                    ) {
                        title.alpha = 0
                    }
                    return
                }
                // Keyframes inside a swipe's animation follow the finger:
                // gone a quarter of the way back.
                UIView.animateKeyframes(withDuration: 0, delay: 0) {
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.25) {
                        title.alpha = 0
                    }
                }
            }, completion: { context in
                if context.isCancelled {
                    title.alpha = 1
                }
            })
        }

        /// Lets go of a cancelled opening as soon as a finger lands anywhere,
        /// so a tap on the playlist it is gliding into opens it again rather
        /// than being ignored. Left alone, iOS finishes the glide by itself.
        private func releaseOnNextTouch() {
            isFinishingCancelledOpening = true
            if let window = viewIfLoaded?.window {
                touchDownWatcher = TouchDownWatcher(in: window) { [weak self] in
                    self?.releaseCancelledOpening()
                }
            }
        }

        private func releaseCancelledOpening() {
            guard isFinishingCancelledOpening else {
                return
            }
            endCancelledOpening()
            // iOS is already taking the screen away; an animated pop on top
            // of that would start a second transition.
            arrival.goBack?(false)
        }

        private func endCancelledOpening() {
            isFinishingCancelledOpening = false
            touchDownWatcher?.remove()
            touchDownWatcher = nil
        }

        private func stopTouches(on screen: UIViewController?) {
            openingStartedAt = nil
            arrival.isSettled = false
            screen?.view.isUserInteractionEnabled = false
            heldScreen = screen
        }

        private func settle() {
            openingStartedAt = nil
            arrival.isSettled = true
            heldScreen?.view.isUserInteractionEnabled = true
            heldScreen = nil
            // A swipe that iOS took and then cancelled leaves the screen
            // here, ready to be swiped again.
            if isTopScreen {
                swipeBack?.isEnabled = true
            }
        }

        // MARK: Swiping back

        private func installSwipeBack(on screen: UIViewController?) {
            guard swipeBack == nil, let screen else {
                return
            }
            let swipeBack = SwipeBackGestureRecognizer(target: self, action: #selector(swipedBack(_:)))
            swipeBack.delegate = self
            swipeBack.cancelsTouchesInView = true
            screen.view.addGestureRecognizer(swipeBack)
            self.swipeBack = swipeBack
            swipeBackScreen = screen
        }

        /// Begins for a swipe back that iOS's swipes passed on, moves the
        /// page with the finger, and ends as the finger lifts from one that
        /// goes back.
        @objc private func swipedBack(_ gesture: SwipeBackGestureRecognizer) {
            switch gesture.state {
            case .began:
                // Buttons wait while the finger is down, and a press or a
                // scroll the finger started ends here.
                arrival.isSettled = false
                gesture.cancelOtherGestures()
                // A screen still zooming open, or one without the zoom,
                // stays put and goes back on lift.
                if #available(iOS 18.0, *), openingStartedAt == nil, let screen = swipeBackScreen {
                    follower = SwipeFollower(screen: screen, touchDown: gesture.touchDownLocation)
                }
                InteractionTrace.note(follower == nil ? "swipe back can't move the page here: acts on lift" : "swipe back moves the page with the finger")
                follower?.follow(gesture.translation, distance: gesture.distance)
            case .changed:
                follower?.follow(gesture.translation, distance: gesture.distance)
            case .ended:
                arrival.isSettled = false
                gesture.isEnabled = false
                goBackOnceZoomedIn()
            case .cancelled, .failed:
                springBack()
                // Still here: the screen settles again, unless it started
                // going away some other way meanwhile.
                if heldScreen == nil, isTopScreen {
                    arrival.isSettled = true
                }
            default:
                break
            }
        }

        /// Puts a page the finger moved back in place.
        private func springBack() {
            guard let follower else {
                return
            }
            self.follower = nil
            follower.springBack()
        }

        /// Goes back once UIKit has finished with the lifted finger, as a
        /// Back tap does, never from inside the finger's own handling while
        /// the screen's gestures are still winding down: flicks that went
        /// back from there showed the Playlists screen, or black, behind the
        /// page's bar buttons for a frame on iPhone before the page began to
        /// shrink. A flick during the zoom-in waits until the zoom has
        /// visibly landed.
        private func goBackOnceZoomedIn() {
            let remainingZoom = openingStartedAt.map {
                Self.visibleZoomDuration - Date.now.timeIntervalSince($0)
            } ?? 0
            if remainingZoom > 0 {
                InteractionTrace.note("going back once the zoom lands, in \(Int(remainingZoom * 1000))ms")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + max(remainingZoom, 0)) { [weak self] in
                self?.goBack()
            }
        }

        private func goBack() {
            guard isTopScreen else {
                springBack()
                return
            }
            InteractionTrace.note("going back")
            arrival.goBack?(true)
            guard follower != nil else {
                return
            }
            // The zoom takes a moved page as it starts. Should nothing go
            // back after all, the page mustn't stay where the finger left it.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.handOverTimeout) { [weak self] in
                guard let self, self.follower != nil else {
                    return
                }
                InteractionTrace.note("nothing went back: the page springs back")
                self.springBack()
                self.settle()
            }
        }

        private var isTopScreen: Bool {
            guard let screen = swipeBackScreen else {
                return false
            }
            return screen.navigationController?.topViewController === screen
        }

        /// One of iOS's own swipes has the screen, or has just let it go.
        private var isIOSSwipeUnderWay: Bool {
            guard let coordinator = navigationController?.transitionCoordinator else {
                return false
            }
            return coordinator.isInteractive || coordinator.initiallyInteractive || coordinator.isCancelled
        }

        /// The swipe goes back only when the screen is still here and none
        /// of iOS's swipes took it meanwhile.
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard gesture === swipeBack else {
                return true
            }
            return isTopScreen && heldScreen == nil && !isIOSSwipeUnderWay
        }

        /// Swipes that start at the leading edge belong to iOS. Controls that
        /// are dragged sideways, such as the Up Next / All Songs switcher,
        /// keep their drags; a swipe that starts on anything else, buttons
        /// and menus included, can still go back.
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gesture === swipeBack, let view = gesture.view else {
                return true
            }
            let x = touch.location(in: view).x
            let fromLeadingEdge = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
                ? view.bounds.width - x
                : x
            guard fromLeadingEdge >= Self.leadingEdgeWidth else {
                return false
            }
            if arrival.sidewaysDragFrame.contains(touch.location(in: nil)) {
                return false
            }
            let isDraggedSideways = sequence(first: touch.view, next: { $0?.superview })
                .prefix { $0 != nil && $0 !== view }
                .contains { $0 is UISegmentedControl || $0 is UISlider || $0 is UISwitch }
            return !isDraggedSideways
        }

        /// Everything on the screen runs alongside this swipe until it
        /// begins, so a button pressed or a list stopped as the finger lands
        /// doesn't end it; once it begins, it cancels them. iOS's swipes back
        /// don't: when one starts, this swipe ends.
        func gestureRecognizer(
            _ gesture: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            guard gesture === swipeBack, let swipe = gesture as? SwipeBackGestureRecognizer else {
                return true
            }
            return !swipe.isIOSSwipeBack(other)
        }

        /// This swipe waits for iOS's swipes back to sort the touch, so it
        /// only gets the swipes they pass on. Nothing waits for it: a button
        /// shows it's pressed at once.
        func gestureRecognizer(
            _ gesture: UIGestureRecognizer,
            shouldRequireFailureOf other: UIGestureRecognizer
        ) -> Bool {
            guard gesture === swipeBack, let swipe = gesture as? SwipeBackGestureRecognizer else {
                return false
            }
            return swipe.isIOSSwipeBack(other)
        }
    }
}

/// Takes a swipe back from the middle of the screen that iOS's swipes passed
/// on, and decides when the finger lifts.
///
/// It waits for iOS's swipes to sort each touch. The zoom's swipe takes a
/// swipe that sets off level or slightly downward, and this one fails. One
/// that drifts up even a little, as a thumb sweeping toward the trailing
/// edge often does, the zoom passes on, and this begins once the finger has
/// gone a few points toward the trailing edge holding roughly level. It
/// ends as the finger lifts: ended if the screen goes back, cancelled if it
/// stays.
///
/// It fails for a tap, a scroll, a swipe toward the leading edge, and any
/// swipe iOS takes. A finger that rests first is sorted once it sets off.
private final class SwipeBackGestureRecognizer: UIGestureRecognizer {
    /// Where the finger landed, in window coordinates: the page moves with
    /// the finger, so the page's own coordinates would move under it.
    private(set) var touchDownLocation: CGPoint = .zero
    private var samples: [(location: CGPoint, time: TimeInterval)] = []
    /// Whether the touch has been sorted as a swipe back, which may still
    /// wait for iOS's swipes to pass on it.
    private var isSwipeBack = false
    /// The touch's other gestures, to cancel once this begins.
    private var otherGestures: [UIGestureRecognizer] = []

    /// How far the finger travels before a swipe is sorted.
    private static let sortingDistance: CGFloat = 10
    /// A swipe that sets off more steeply than this is a scroll. Sorting on
    /// both directions, not on the distance travelled, keeps a quick
    /// vertical flick from passing for a swipe back before it has gone far
    /// enough to look like a scroll.
    private static let steepestSlope: CGFloat = 0.5
    /// A flick toward the trailing edge goes back from any distance past a
    /// small one, and a flick toward the leading edge stays.
    private static let flickSpeed: CGFloat = 300
    private static let flickDistance: CGFloat = 16
    /// An unhurried swipe goes back once it has passed this much of the
    /// width, as the zoom's own swipe does.
    private static let goingBackFraction: CGFloat = 1 / 3

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

    /// How fast the finger was last moving toward the trailing edge, in
    /// points per second.
    private var speed: CGFloat {
        guard let last = samples.last,
              let first = samples.first(where: { last.time - $0.time <= 0.06 }),
              last.time > first.time else {
            return 0
        }
        return (last.location.x - first.location.x) * towardTrailing / (last.time - first.time)
    }

    private var towardTrailing: CGFloat {
        view?.effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1
    }

    private var isGoingBack: Bool {
        let width = view?.bounds.width ?? 0
        if speed >= Self.flickSpeed {
            return distance >= Self.flickDistance
        }
        return width > 0 && distance >= width * Self.goingBackFraction && speed > -Self.flickSpeed
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        // One finger only; a second one ends the swipe.
        guard samples.isEmpty, touches.count == 1, let touch = touches.first else {
            end(goingBack: false)
            return
        }
        touchDownLocation = touch.location(in: nil)
        samples = [(touchDownLocation, touch.timestamp)]
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first else {
            return
        }
        samples.append((touch.location(in: nil), touch.timestamp))
        samples.removeAll { touch.timestamp - $0.time > 0.1 }

        switch state {
        case .began, .changed:
            state = .changed
            return
        case .possible:
            break
        default:
            return
        }
        // Sorted already, and waiting for iOS's swipes to pass on it.
        guard !isSwipeBack else {
            return
        }
        let rise = abs(translation.y)
        guard max(abs(distance), rise) >= Self.sortingDistance else {
            return
        }
        guard distance > 0, rise <= distance * Self.steepestSlope else {
            InteractionTrace.note("swipe back leaves it: \(distance > 0 ? "a scroll" : "not toward the trailing edge")")
            state = .failed
            return
        }
        InteractionTrace.note("swipe back sorted at \(Int(distance)) pt, \(Int(speed)) pt/s: takes it if iOS passes on it")
        isSwipeBack = true
        // Only the screen's own; system gestures above it stay.
        otherGestures = (touch.gestureRecognizers ?? []).filter { other in
            guard let view, let otherView = other.view else {
                return false
            }
            return other !== self && !isIOSSwipeBack(other) && otherView.isDescendant(of: view)
        }
        state = .began
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        // A finger that lifts where it last moved keeps its speed.
        if let touch = touches.first, touch.location(in: nil) != samples.last?.location {
            samples.append((touch.location(in: nil), touch.timestamp))
        }
        let goesBack = isGoingBack
        if state == .began || state == .changed {
            InteractionTrace.note("swipe back lifted at \(Int(distance)) pt, \(Int(speed)) pt/s: \(goesBack ? "goes back" : "stays")")
        }
        end(goingBack: goesBack)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        end(goingBack: false)
    }

    override func reset() {
        super.reset()
        samples = []
        isSwipeBack = false
        otherGestures = []
    }

    /// iOS's own swipes back, the zoom's or the navigation stack's: pans
    /// attached to this screen or above it, other than a list's scrolling.
    func isIOSSwipeBack(_ other: UIGestureRecognizer) -> Bool {
        guard other !== self,
              other is UIPanGestureRecognizer,
              let view,
              let otherView = other.view,
              !(otherView is UIScrollView) else {
            return false
        }
        return view.isDescendant(of: otherView)
    }

    /// Ends whatever else the finger started, such as a button's press or
    /// the list's scrolling, as iOS's own swipes back do. Switching a
    /// gesture off and on again cancels it.
    func cancelOtherGestures() {
        for gesture in otherGestures where gesture.isEnabled {
            gesture.isEnabled = false
            gesture.isEnabled = true
        }
        otherGestures = []
    }

    private func end(goingBack: Bool) {
        switch state {
        case .possible:
            state = .failed
        case .began, .changed:
            state = goingBack ? .ended : .cancelled
        default:
            break
        }
    }
}

/// Moves a page with the finger during a swipe back that the zoom's own
/// swipe passed on, the way the zoom's swipe would: the page shrinks into a
/// card that follows the finger, over the screen beneath it, which sits a
/// little back and dims.
///
/// That is exactly where the zoom puts the screen beneath on the first frame
/// of taking a page away, measured from recordings, so letting go hands over
/// without a jump: the zoom shrinks the page into its cover, and the card
/// eases back into the page's place inside it, in step with the zoom's own
/// animation, so it lands on the cover.
///
/// The screen beneath is set back as the zoom does it: the real screen
/// stays full size underneath, put back under the page as UIKit does when
/// its own swipes begin, and a picture of it sits back on top, so the real
/// screen's edges fill the margin around the picture.
@MainActor
private final class SwipeFollower {
    /// How far the zoom sets the screen beneath back and dims it while its
    /// swipe follows a finger, and on the first frame of taking a page away.
    private static let backdropScale: CGFloat = 0.913
    private static let backdropDimming: CGFloat = 0.12
    /// How small the card gets, and over what share of the width; the
    /// zoom's own card shrinks at about the same rate.
    private static let smallestScale: CGFloat = 0.8
    private static let shrinkingFraction: CGFloat = 0.4
    private static let cornerRadius: CGFloat = 44
    /// The page may start moving a few points after the finger, once iOS's
    /// swipes have passed on the touch; it catches up over this long rather
    /// than jumping.
    private static let catchUpDuration: TimeInterval = 0.12
    /// Toward the leading edge the card holds back this much.
    private static let leadingResistance: CGFloat = 0.2

    private weak var screen: UIViewController?
    private let page: UIView
    private let backdrop: UIView
    private weak var container: UIView?
    /// The picture of the screen beneath that sits back.
    private var picture: UIView?
    private let dimming = UIView()
    /// Where the finger landed, from the page's centre; the card shrinks
    /// toward it, so the finger keeps hold of the same spot.
    private let grip: CGVector
    private let startedAt = Date.now
    private let pageCorners: (radius: CGFloat, curve: CALayerCornerCurve, masks: Bool)
    private var isFollowing = true

    /// Fails unless the page is the stack's settled top screen.
    init?(screen: UIViewController, touchDown: CGPoint) {
        guard let navigationController = screen.navigationController,
              navigationController.topViewController === screen,
              navigationController.transitionCoordinator == nil,
              let index = navigationController.viewControllers.firstIndex(of: screen), index > 0,
              let container = screen.view.superview,
              screen.view.transform.isIdentity else {
            return nil
        }
        let beneath = navigationController.viewControllers[index - 1]
        guard beneath.isViewLoaded, beneath.view.superview == nil else {
            return nil
        }
        self.screen = screen
        self.container = container
        page = screen.view
        backdrop = beneath.view
        let layer = page.layer
        pageCorners = (layer.cornerRadius, layer.cornerCurve, layer.masksToBounds)
        let point = container.convert(touchDown, from: nil)
        grip = CGVector(dx: point.x - page.center.x, dy: point.y - page.center.y)

        backdrop.transform = .identity
        backdrop.bounds = page.bounds
        backdrop.center = page.center
        container.insertSubview(backdrop, belowSubview: page)
        dimming.backgroundColor = .black
        dimming.alpha = 0
        dimming.isUserInteractionEnabled = false
        dimming.frame = container.bounds
        dimming.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.insertSubview(dimming, belowSubview: page)
        layer.cornerCurve = .continuous
        layer.cornerRadius = Self.cornerRadius
        layer.masksToBounds = true
        UIView.animate(springDuration: 0.25, bounce: 0) {
            self.dimming.alpha = Self.backdropDimming
        }
        // The screen beneath draws once it's back in the window; until its
        // picture is ready, the screen itself shows exactly where the
        // picture starts.
        DispatchQueue.main.async {
            self.setBackdropBack()
        }
    }

    private func setBackdropBack() {
        guard isFollowing,
              let container,
              backdrop.superview === container,
              let picture = backdrop.snapshotView(afterScreenUpdates: false) else {
            return
        }
        picture.isUserInteractionEnabled = false
        picture.bounds = backdrop.bounds
        picture.center = backdrop.center
        container.insertSubview(picture, aboveSubview: backdrop)
        self.picture = picture
        UIView.animate(springDuration: 0.25, bounce: 0) {
            picture.transform = CGAffineTransform(scaleX: Self.backdropScale, y: Self.backdropScale)
        }
    }

    /// Puts the card under the finger, `distance` toward the trailing edge.
    func follow(_ translation: CGPoint, distance: CGFloat) {
        let width = max(page.bounds.width, 1)
        let shrink = min(max(distance, 0) / (width * Self.shrinkingFraction), 1)
        let scale = 1 - (1 - Self.smallestScale) * shrink
        let x = distance >= 0 ? translation.x : translation.x * Self.leadingResistance
        let transform = CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: grip.dx * (1 - scale) + x,
            ty: grip.dy * (1 - scale) + translation.y
        )
        guard Date.now.timeIntervalSince(startedAt) < Self.catchUpDuration else {
            page.transform = transform
            return
        }
        UIView.animate(
            withDuration: 0.08,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
        ) {
            self.page.transform = transform
        }
    }

    /// The page is going back: the zoom takes it from here. Without an
    /// animation, it just goes.
    func handOver(to coordinator: UIViewControllerTransitionCoordinator?) {
        isFollowing = false
        // In the same frame as the zoom's first: the zoom sets the screen
        // beneath back and dims it itself, just as this had it.
        UIView.performWithoutAnimation {
            picture?.removeFromSuperview()
            picture = nil
            dimming.removeFromSuperview()
        }
        guard let coordinator else {
            restorePage()
            return
        }
        InteractionTrace.note("the zoom takes the page from the finger")
        coordinator.animate(alongsideTransition: { _ in
            self.page.transform = .identity
        }, completion: { context in
            self.restorePage()
            if context.isCancelled {
                self.removeBackdrop()
            }
        })
    }

    /// The page stays: everything goes back in place.
    func springBack() {
        isFollowing = false
        InteractionTrace.note("the page springs back")
        UIView.animate(springDuration: 0.35, bounce: 0) {
            self.page.transform = .identity
            self.picture?.transform = .identity
            self.dimming.alpha = 0
        } completion: { _ in
            self.picture?.removeFromSuperview()
            self.picture = nil
            self.dimming.removeFromSuperview()
            self.tidyUp()
        }
    }

    /// Puts the page and the screen beneath back as they were, once nothing
    /// else is moving them: a Back tap meanwhile, say.
    private func tidyUp() {
        if let coordinator = screen?.navigationController?.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in
                self.tidyUp()
            }
            return
        }
        restorePage()
        removeBackdrop()
    }

    private func restorePage() {
        page.transform = .identity
        page.layer.cornerRadius = pageCorners.radius
        page.layer.cornerCurve = pageCorners.curve
        page.layer.masksToBounds = pageCorners.masks
    }

    /// Takes the screen beneath back out, unless UIKit has taken it into a
    /// transition meanwhile.
    private func removeBackdrop() {
        guard let screen,
              let navigationController = screen.navigationController,
              navigationController.topViewController === screen,
              navigationController.transitionCoordinator == nil,
              backdrop.superview === container else {
            return
        }
        backdrop.removeFromSuperview()
    }
}

/// Calls back the moment a finger lands anywhere in a window, without
/// taking the touch from anything.
@MainActor
private final class TouchDownWatcher: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let onTouchDown: () -> Void

    init(in window: UIWindow, onTouchDown: @escaping () -> Void) {
        self.onTouchDown = onTouchDown
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
        window.addGestureRecognizer(self)
    }

    func remove() {
        view?.removeGestureRecognizer(self)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        state = .failed
        DispatchQueue.main.async { [self] in
            onTouchDown()
        }
    }

    func gestureRecognizer(
        _ gesture: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

// MARK: - Segmented switcher

/// A segmented control drawn in SwiftUI, used on iOS 26 and later. There the
/// system's segmented control draws its selected label through Liquid Glass,
/// and while a swipe back shrinks the page to follow the finger, the glass
/// applied the shrink a second time, so the selected label showed up twice.
/// This one keeps a Liquid Glass thumb but draws the labels above it, never
/// through it, so they shrink with the page like everything else.
///
/// Tap a segment or drag the thumb across, as with the system control; the
/// thumb lifts a little while a finger is on it, and the change animates
/// with the binding's animation. Its frame is kept in the screen's
/// `ScreenArrival`, so a drag on it never turns into a swipe back, and
/// VoiceOver sees a standard segmented picker.
@available(iOS 26.0, *)
struct SegmentedSwitcher<Value: Hashable>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.screenArrival) private var screenArrival
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [(value: Value, label: Text)]
    /// The segment under the finger while it is down.
    @State private var trackedValue: Value?
    @State private var width: CGFloat = 0
    @Namespace private var thumbSpace

    private static var inset: CGFloat { 2 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isShown = option.value == (trackedValue ?? selection)
                option.label
                    .font(.subheadline.weight(isShown ? .semibold : .medium))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background {
                        if isShown {
                            thumb
                                .matchedGeometryEffect(id: "thumb", in: thumbSpace)
                        }
                    }
            }
        }
        .padding(Self.inset)
        .background(Color.primary.opacity(0.08), in: Capsule())
        .contentShape(Capsule())
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            screenArrival?.sidewaysDragFrame = frame
        }
        .onDisappear {
            screenArrival?.sidewaysDragFrame = .null
        }
        .gesture(drag)
        .accessibilityRepresentation {
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { index in
                    options[index].label.tag(options[index].value)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    /// Liquid Glass, tinted white on the light page so it stands clear of
    /// the track, and lifted while a finger is on the switcher.
    private var thumb: some View {
        let glass: Glass = colorScheme == .dark ? .regular : .regular.tint(Color.white.opacity(0.6))
        return Color.clear
            .glassEffect(glass.interactive(), in: Capsule())
            .scaleEffect(trackedValue != nil && !reduceMotion ? 1.06 : 1)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let segment = option(at: value.location.x)
                guard segment != trackedValue else {
                    return
                }
                withAnimation(reduceMotion ? nil : .strongEaseOut(duration: 0.2)) {
                    trackedValue = segment
                }
            }
            .onEnded { value in
                let chosen = option(at: value.location.x)
                // A drag that went up or down was meant for the list, so it
                // leaves the switcher as it was.
                let isVertical = abs(value.translation.height) > max(20, abs(value.translation.width))
                withAnimation(reduceMotion ? nil : .strongEaseOut(duration: 0.2)) {
                    trackedValue = nil
                }
                if !isVertical, chosen != selection {
                    selection = chosen
                }
            }
    }

    private func option(at x: CGFloat) -> Value {
        let segmentWidth = (width - Self.inset * 2) / CGFloat(max(options.count, 1))
        guard segmentWidth > 0, !options.isEmpty else {
            return selection
        }
        let index = Int(((x - Self.inset) / segmentWidth).rounded(.down))
        return options[min(max(index, 0), options.count - 1)].value
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
func artworkCornerRadius(for size: CGFloat) -> CGFloat {
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
