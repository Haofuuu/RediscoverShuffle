import SwiftUI
import UIKit
#if DEBUG
import os
#endif

/// Notes a decision the app made about a touch, such as how it sorted a
/// swipe back, in the touch log that debug builds keep while Show Touches is
/// on. Release builds compile this to nothing and never build the message.
enum InteractionTrace {
    @MainActor
    static func note(_ message: @autoclosure () -> String) {
        #if DEBUG
        TouchInspector.shared.note(message())
        #endif
    }
}

extension View {
    /// In debug builds, draws every touch and logs which gesture took it
    /// while Show Touches is on in Settings. Does nothing in release builds.
    func touchInspector() -> some View {
        #if DEBUG
        modifier(TouchInspectorModifier())
        #else
        self
        #endif
    }
}

#if DEBUG

// MARK: - Settings

/// The Developer section of Settings in debug builds. Its text isn't
/// localized, since it never ships.
struct TouchInspectorSettingsSection: View {
    @AppStorage(TouchInspector.enabledKey) private var showsTouches = false

    var body: some View {
        Section {
            Toggle(isOn: $showsTouches) {
                Label {
                    Text(verbatim: "Show Touches")
                } icon: {
                    Image(systemName: "hand.tap")
                }
            }
            if showsTouches || FileManager.default.fileExists(atPath: TouchInspector.logURL.path(percentEncoded: false)) {
                ShareLink(item: TouchInspector.logURL) {
                    Label {
                        Text(verbatim: "Share Touch Log")
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        } header: {
            Text(verbatim: "Developer")
        } footer: {
            Text(verbatim: "Debug builds only. Draws each touch and its path, shows which gesture took it, and keeps a timed log, for screen recordings. The log starts over each launch.")
        }
    }
}

// MARK: - Hooking into the window

private struct TouchInspectorModifier: ViewModifier {
    @AppStorage(TouchInspector.enabledKey) private var isEnabled = false

    func body(content: Content) -> some View {
        content.background {
            TouchInspectorAnchor(isEnabled: isEnabled)
        }
    }
}

/// Finds the app's window and turns the inspector on or off there.
private struct TouchInspectorAnchor: UIViewRepresentable {
    let isEnabled: Bool

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        view.isEnabled = isEnabled
    }

    final class AnchorView: UIView {
        var isEnabled = false {
            didSet {
                update()
            }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            update()
        }

        private func update() {
            guard let window else {
                return
            }
            TouchInspector.shared.update(window: window, isEnabled: isEnabled)
        }
    }
}

// MARK: - Inspector

/// Shows every touch in the app's window, with its path and the gestures
/// that took it, and logs touches, gestures, the app's own decisions and
/// late frames with millisecond timing, so a screen recording shows exactly
/// how the app responded.
///
/// It only watches. Touches reach it through a gesture of its own on the
/// window that never recognizes, runs alongside every other gesture and
/// delays nothing, and it draws in a separate window that never takes
/// touches. To see when other gestures begin or end, it adds itself as one
/// more target of each gesture under the finger, which UIKit calls as the
/// gesture changes state, and reads their state once a frame for failures.
///
/// Turn it on with Show Touches in Settings, or launch with
/// `-debugShowTouches YES`. The log goes to the Xcode console, to Console
/// under the "Touches" category, and to a file that Settings can share.
@MainActor
final class TouchInspector: NSObject {
    static let shared = TouchInspector()

    nonisolated static let enabledKey = "debugShowTouches"
    nonisolated static let logURL = URL.cachesDirectory.appending(path: "TouchLog.txt")

    /// How long after the last touch or note the clock keeps running and
    /// gestures stay watched; a touch after this starts a new timeline.
    private static let quietAfter: TimeInterval = 2
    /// A gap this long between frames means the main thread was busy.
    private static let lateFrame: CFTimeInterval = 0.05
    /// A moving finger is logged at most this often.
    private static let moveLogInterval: TimeInterval = 0.05

    private weak var appWindow: UIWindow?
    private var observer: TouchObserver?
    private var overlay: OverlayWindow?
    private var logFile: LogFile?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RediscoverShuffle", category: "Touches")

    private var touches: [ObjectIdentifier: TrackedTouch] = [:]
    private var traces: [Int: TouchTrace] = [:]
    private var gestures: [ObjectIdentifier: WatchedGesture] = [:]
    private let controls = NSHashTable<UIControl>.weakObjects()
    private var touchCount = 0
    /// When the current timeline started; log times count from here.
    private var epoch: TimeInterval?
    private var lastActivity: TimeInterval = 0
    private var displayLink: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    override private init() {
        super.init()
    }

    func update(window: UIWindow, isEnabled: Bool) {
        guard isEnabled else {
            stop()
            return
        }
        guard observer == nil || appWindow !== window else {
            return
        }
        stop()
        start(in: window)
    }

    func note(_ message: @autoclosure () -> String) {
        guard observer != nil else {
            return
        }
        logEvent("app: " + message())
    }

    /// Logs something that happened outside a touch's own events.
    private func logEvent(_ line: String) {
        let now = CACurrentMediaTime()
        beginTimelineIfQuiet(at: now)
        log(line, at: now)
        keepWatching(at: now)
    }

    // MARK: Starting and stopping

    private func start(in window: UIWindow) {
        guard let scene = window.windowScene else {
            return
        }
        appWindow = window
        let observer = TouchObserver { [weak self] phase, touches in
            self?.handle(phase, touches)
        }
        window.addGestureRecognizer(observer)
        self.observer = observer

        let overlay = OverlayWindow(windowScene: scene)
        overlay.isHidden = false
        self.overlay = overlay

        logFile = LogFile(url: Self.logURL)
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))"
        let size = window.bounds.size
        write("Show Touches on: \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion), app \(version), window \(Int(size.width))×\(Int(size.height)) pt")
    }

    private func stop() {
        guard observer != nil || overlay != nil else {
            return
        }
        if let observer {
            observer.view?.removeGestureRecognizer(observer)
        }
        observer = nil
        overlay?.isHidden = true
        overlay = nil
        displayLink?.invalidate()
        displayLink = nil
        lastFrame = 0
        unwatchAll()
        touches = [:]
        traces = [:]
        epoch = nil
        write("Show Touches off")
        logFile?.close()
        logFile = nil
    }

    // MARK: Touches

    private func handle(_ phase: UITouch.Phase, _ changed: Set<UITouch>) {
        guard let canvas = overlay?.canvas else {
            return
        }
        for touch in changed.sorted(by: { $0.timestamp < $1.timestamp }) {
            let point = touch.location(in: canvas)
            switch phase {
            case .began:
                touchBegan(touch, at: point, in: canvas)
            case .moved:
                touchMoved(touch, at: point)
            case .ended, .cancelled:
                touchEnded(touch, at: point, cancelled: phase == .cancelled)
            default:
                break
            }
        }
        keepWatching(at: CACurrentMediaTime())
    }

    private func touchBegan(_ touch: UITouch, at point: CGPoint, in canvas: CanvasView) {
        let time = touch.timestamp
        let now = CACurrentMediaTime()
        beginTimelineIfQuiet(at: min(time, now))
        touchCount += 1
        let number = touchCount
        let trace = TouchTrace(number: number, at: point, in: canvas)
        traces[number] = trace
        touches[ObjectIdentifier(touch)] = TrackedTouch(
            number: number,
            touch: touch,
            start: point,
            startTime: time,
            samples: [(point, time)],
            lastLoggedMove: time
        )

        let watched = watch(touch.gestureRecognizers ?? [], for: number)
        var target = touch.view.map { Self.shortTypeName(of: $0) } ?? "nothing"
        if let control = Self.nearestControl(to: touch.view) {
            watch(control)
            if control !== touch.view {
                target += " in \(Self.shortTypeName(of: control))"
            }
        }
        log(
            "#\(number) down at \(Self.format(point)) on \(target)",
            detail: "gestures: " + (watched.isEmpty ? "none" : watched.joined(separator: ", ")),
            at: now
        )
    }

    private func touchMoved(_ touch: UITouch, at point: CGPoint) {
        let id = ObjectIdentifier(touch)
        guard var tracked = touches[id] else {
            return
        }
        let time = touch.timestamp
        tracked.samples.append((point, time))
        tracked.samples.removeAll { time - $0.time > 0.1 }
        traces[tracked.number]?.move(to: point)
        if time - tracked.lastLoggedMove >= Self.moveLogInterval {
            tracked.lastLoggedMove = time
            let velocity = Self.velocity(of: tracked.samples)
            log(
                "#\(tracked.number) at \(Self.format(point)), moved \(Self.format(point - tracked.start)), \(Self.format(velocity)) pt/s",
                at: CACurrentMediaTime(),
                onScreen: false
            )
        }
        touches[id] = tracked
    }

    private func touchEnded(_ touch: UITouch, at point: CGPoint, cancelled: Bool) {
        let id = ObjectIdentifier(touch)
        guard var tracked = touches.removeValue(forKey: id) else {
            return
        }
        let time = touch.timestamp
        tracked.samples.append((point, time))
        let velocity = Self.velocity(of: tracked.samples)
        let duration = Int(((time - tracked.startTime) * 1000).rounded())
        traces[tracked.number]?.move(to: point)
        finishTrace(tracked.number, cancelled: cancelled)
        log(
            "#\(tracked.number) \(cancelled ? "cancelled" : "up") at \(Self.format(point)), moved \(Self.format(point - tracked.start)) in \(duration)ms, \(Self.format(velocity)) pt/s",
            at: CACurrentMediaTime()
        )
    }

    private func finishTrace(_ number: Int, cancelled: Bool) {
        traces[number]?.finish(cancelled: cancelled) { [weak self] in
            self?.traces[number] = nil
        }
    }

    /// Drops touches UIKit has finished with but never reported, so the
    /// clock can stop.
    private func sweepFinishedTouches() {
        for (id, tracked) in touches {
            if let phase = tracked.touch?.phase, phase != .ended, phase != .cancelled {
                continue
            }
            touches[id] = nil
            finishTrace(tracked.number, cancelled: true)
        }
    }

    // MARK: Gestures

    /// Starts watching the gestures that receive a touch, and returns their
    /// names.
    private func watch(_ list: [UIGestureRecognizer], for number: Int) -> [String] {
        var names: [String] = []
        for gesture in list where gesture !== observer {
            let id = ObjectIdentifier(gesture)
            if gestures[id] == nil {
                let info = GestureInfo(gesture)
                guard info.kind != .ignored else {
                    continue
                }
                if info.kind == .followed {
                    gesture.addTarget(self, action: #selector(gestureChanged(_:)))
                }
                gestures[id] = WatchedGesture(gesture: gesture, info: info, state: gesture.state)
            }
            gestures[id]?.touchNumbers.insert(number)
            if let name = gestures[id]?.info.name {
                names.append(gesture.isEnabled ? name : name + " (off)")
            }
        }
        return names
    }

    private func watch(_ control: UIControl) {
        guard !controls.contains(control) else {
            return
        }
        controls.add(control)
        control.addTarget(self, action: #selector(controlTouchedUpInside(_:)), for: .touchUpInside)
        control.addTarget(self, action: #selector(controlValueChanged(_:)), for: .valueChanged)
    }

    private func unwatchAll() {
        for watched in gestures.values where watched.info.kind == .followed {
            watched.gesture?.removeTarget(self, action: #selector(gestureChanged(_:)))
        }
        gestures = [:]
        for control in controls.allObjects {
            control.removeTarget(self, action: nil, for: .allEvents)
        }
        controls.removeAllObjects()
    }

    @objc private func gestureChanged(_ gesture: UIGestureRecognizer) {
        record(gesture, state: gesture.state)
    }

    /// Catches what targets aren't told: failures, and the gestures only
    /// read, never followed.
    private func pollGestures() {
        for (id, watched) in gestures {
            guard let gesture = watched.gesture else {
                gestures[id] = nil
                continue
            }
            let state = gesture.state
            if state != watched.state, state == .failed || watched.info.kind == .polled {
                record(gesture, state: state)
            }
        }
    }

    private func record(_ gesture: UIGestureRecognizer, state: UIGestureRecognizer.State) {
        let id = ObjectIdentifier(gesture)
        guard var watched = gestures[id] else {
            return
        }
        let previous = watched.state
        watched.state = state
        gestures[id] = watched
        let word: String
        switch state {
        case .began:
            word = "began"
        case .ended:
            word = "ended"
        case .cancelled:
            word = "cancelled"
        case .failed:
            guard previous != .failed else {
                return
            }
            word = "failed"
        default:
            return
        }
        if state == .began || state == .ended || state == .cancelled {
            for number in watched.touchNumbers {
                traces[number]?.mark(watched.info.name, cancelled: state == .cancelled)
            }
        }
        let now = CACurrentMediaTime()
        let touchList = watched.touchNumbers.sorted().map { "#\($0)" }.joined(separator: " ")
        log("\(watched.info.name) \(word) (\(touchList))", detail: watched.info.detail, at: now, onScreen: state != .failed)
        keepWatching(at: now)
    }

    @objc private func controlTouchedUpInside(_ control: UIControl) {
        logEvent("\(Self.shortTypeName(of: control)) tapped")
    }

    @objc private func controlValueChanged(_ control: UIControl) {
        logEvent("\(Self.shortTypeName(of: control)) value changed")
    }

    // MARK: Clock

    private func beginTimelineIfQuiet(at time: TimeInterval) {
        guard touches.isEmpty, epoch == nil || time - lastActivity > Self.quietAfter else {
            return
        }
        epoch = time
        write("────────")
    }

    private func keepWatching(at time: TimeInterval) {
        lastActivity = max(lastActivity, time)
        guard displayLink == nil, overlay != nil else {
            return
        }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if lastFrame > 0, now - lastFrame > Self.lateFrame {
            log("frame late by \(Int(((now - lastFrame) * 1000).rounded()))ms: main thread busy", at: now)
        }
        lastFrame = now
        sweepFinishedTouches()
        pollGestures()
        let elapsed = now - (epoch ?? now)
        let quiet = touches.isEmpty && now - lastActivity > Self.quietAfter
        overlay?.canvas.hud.setClock(
            String(format: "t+%.3f s", elapsed) + (quiet ? "  ·  idle" : "  ·  \(touches.count) down")
        )
        if quiet {
            link.invalidate()
            displayLink = nil
            lastFrame = 0
            unwatchAll()
        }
    }

    // MARK: Writing

    private func log(_ line: String, detail: String? = nil, at time: TimeInterval, onScreen: Bool = true) {
        let elapsed = Int(((time - (epoch ?? time)) * 1000).rounded())
        if onScreen {
            overlay?.canvas.hud.append("+\(elapsed) \(line)")
        }
        write("+\(elapsed)ms \(line)" + (detail.map { "  [\($0)]" } ?? ""))
    }

    private func write(_ text: String) {
        let line = Self.clockFormatter.string(from: .now) + " " + text
        logger.log("\(line, privacy: .public)")
        logFile?.write(line)
    }

    // MARK: Formatting

    private static func velocity(of samples: [(point: CGPoint, time: TimeInterval)]) -> CGPoint {
        guard let last = samples.last,
              let first = samples.first(where: { last.time - $0.time <= 0.06 }),
              last.time > first.time else {
            return .zero
        }
        let elapsed = last.time - first.time
        return CGPoint(
            x: (last.point.x - first.point.x) / elapsed,
            y: (last.point.y - first.point.y) / elapsed
        )
    }

    private static func format(_ point: CGPoint) -> String {
        "\(Int(point.x.rounded())),\(Int(point.y.rounded()))"
    }

    static func shortTypeName(of object: AnyObject) -> String {
        let name = String(describing: type(of: object))
        guard let bracket = name.firstIndex(of: "<") else {
            return name
        }
        return String(name[..<bracket]) + "<…>"
    }

    private static func nearestControl(to view: UIView?) -> UIControl? {
        sequence(first: view, next: { $0?.superview })
            .lazy
            .compactMap { $0 as? UIControl }
            .first
    }
}

private extension CGPoint {
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
}

// MARK: - Model

private struct TrackedTouch {
    let number: Int
    weak var touch: UITouch?
    let start: CGPoint
    let startTime: TimeInterval
    var samples: [(point: CGPoint, time: TimeInterval)]
    var lastLoggedMove: TimeInterval
}

private struct WatchedGesture {
    weak var gesture: UIGestureRecognizer?
    let info: GestureInfo
    var state: UIGestureRecognizer.State
    var touchNumbers: Set<Int> = []
}

/// A readable name for a gesture, and how closely to watch it.
private struct GestureInfo {
    enum Kind {
        /// Bookkeeping gestures that never take a touch.
        case ignored
        /// Read once a frame only.
        case polled
        /// Followed through its targets, and read once a frame for failures.
        case followed
    }

    let name: String
    let detail: String
    let kind: Kind

    @MainActor
    init(_ gesture: UIGestureRecognizer) {
        let type = String(describing: Swift.type(of: gesture))
        let label = (gesture.name ?? "").replacingOccurrences(of: "com.apple.UIKit.", with: "")
        let host = gesture.view.map { TouchInspector.shortTypeName(of: $0) } ?? "no view"
        detail = (label.isEmpty ? type : "\(type) \"\(label)\"") + " on \(host)"

        let bookkeeping = [
            "Relationship", "TouchDurationObserving", "DelayedTouchesBegan", "SecondaryClickDriver",
            "TouchObserver",
        ]
        if bookkeeping.contains(where: type.contains) {
            kind = .ignored
        } else if type.contains("SystemGestureGate") || label.contains("HomeAffordance") {
            kind = .polled
        } else {
            kind = .followed
        }

        if type == "PageSwipeGestureRecognizer" {
            name = "page swipe back"
        } else if gesture is UIScreenEdgePanGestureRecognizer || type.contains("ParallaxTransitionPan") {
            name = "edge swipe back"
        } else if type.contains("ContentSwipeDismiss") {
            name = "content swipe back"
        } else if type.contains("ScrollViewPan") {
            name = "scroll"
        } else if type.contains("SwipeActionPan") {
            name = "row swipe actions"
        } else if type.contains("Drag") {
            name = "drag"
        } else if label.contains("HomeAffordance") {
            name = "home gesture"
        } else if type.contains("SystemGestureGate") {
            name = "system gesture"
        } else if type.contains("FlexInteraction") {
            name = "glass button flex"
        } else if !label.isEmpty {
            name = String(label.prefix { $0 != "<" })
        } else if type.contains("ResponderGestureRecognizer") {
            name = "SwiftUI gesture"
        } else if gesture is UILongPressGestureRecognizer {
            name = "long press"
        } else if gesture is UITapGestureRecognizer {
            name = "tap"
        } else {
            name = type
        }
    }
}

// MARK: - Touch observer

/// Receives every touch in the window and never takes one: it never
/// recognizes, runs alongside everything, can't be stopped by other
/// gestures, and delays nothing.
private final class TouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let onTouches: @MainActor (UITouch.Phase, Set<UITouch>) -> Void

    init(onTouches: @escaping @MainActor (UITouch.Phase, Set<UITouch>) -> Void) {
        self.onTouches = onTouches
        super.init(target: nil, action: nil)
        name = "TouchInspector"
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        requiresExclusiveTouchType = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        onTouches(.began, touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        onTouches(.moved, touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        onTouches(.ended, touches)
        failOnceEveryFingerIsUp(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        onTouches(.cancelled, touches)
        failOnceEveryFingerIsUp(event)
    }

    /// Failing resets it for the next touch; failing earlier would miss
    /// the other fingers.
    private func failOnceEveryFingerIsUp(_ event: UIEvent) {
        let fingerStillDown = (event.allTouches ?? []).contains { $0.phase != .ended && $0.phase != .cancelled }
        if !fingerStillDown {
            state = .failed
        }
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

// MARK: - Drawing

/// A window above everything, alerts included, that never takes a touch.
private final class OverlayWindow: UIWindow {
    let canvas = CanvasView()

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        setUp()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    private func setUp() {
        windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        canvas.frame = bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(canvas)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        false
    }
}

private final class CanvasView: UIView {
    let hud = HUDView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        addSubview(hud)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = min(bounds.width - 16, 520)
        let height = hud.preferredHeight
        let bottom = max(safeAreaInsets.bottom, 8)
        hud.frame = CGRect(
            x: (bounds.width - width) / 2,
            y: bounds.height - bottom - height - 4,
            width: width,
            height: height
        )
    }
}

/// A running clock and the latest log lines, at the bottom of the screen.
private final class HUDView: UIView {
    private let clock = UILabel()
    private let lines: [UILabel]
    private var entries: [String] = []
    private static let lineCount = 5
    private static let padding: CGFloat = 8
    private static let clockHeight: CGFloat = 15
    private static let lineHeight: CGFloat = 13

    var preferredHeight: CGFloat {
        Self.padding * 2 + Self.clockHeight + 2 + CGFloat(Self.lineCount) * Self.lineHeight
    }

    override init(frame: CGRect) {
        lines = (0..<Self.lineCount).map { _ in
            let label = UILabel()
            label.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            label.textColor = .white
            label.lineBreakMode = .byTruncatingTail
            return label
        }
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor.black.withAlphaComponent(0.8)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        clock.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        clock.textColor = .systemYellow
        clock.text = "Show Touches  ·  waiting for a touch"
        addSubview(clock)
        for label in lines {
            addSubview(label)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setClock(_ text: String) {
        clock.text = text
    }

    func append(_ entry: String) {
        entries.append(entry)
        if entries.count > Self.lineCount {
            entries.removeFirst(entries.count - Self.lineCount)
        }
        for (index, label) in lines.enumerated() {
            label.text = index < entries.count ? entries[index] : nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width - Self.padding * 2
        clock.frame = CGRect(x: Self.padding, y: Self.padding, width: width, height: Self.clockHeight)
        for (index, label) in lines.enumerated() {
            label.frame = CGRect(
                x: Self.padding,
                y: Self.padding + Self.clockHeight + 2 + CGFloat(index) * Self.lineHeight,
                width: width,
                height: Self.lineHeight
            )
        }
    }
}

/// One finger: a ring where it is, the path it took, and a tag naming the
/// gestures that took it.
@MainActor
private final class TouchTrace {
    private let ring = CAShapeLayer()
    private let trailOutline = CAShapeLayer()
    private let trail = CAShapeLayer()
    private let tag = TagLabel()
    private let number: Int
    private var takers: [String] = []
    private var points: [CGPoint] = []
    private weak var canvas: UIView?
    private static let radius: CGFloat = 22
    private static let maxPoints = 600

    init(number: Int, at point: CGPoint, in canvas: UIView) {
        self.number = number
        self.canvas = canvas

        let circle = UIBezierPath(
            ovalIn: CGRect(x: -Self.radius, y: -Self.radius, width: Self.radius * 2, height: Self.radius * 2)
        ).cgPath
        ring.path = circle
        ring.fillColor = UIColor.white.withAlphaComponent(0.3).cgColor
        ring.strokeColor = UIColor.white.cgColor
        ring.lineWidth = 2.5
        ring.shadowPath = circle
        ring.shadowColor = UIColor.black.cgColor
        ring.shadowOpacity = 0.45
        ring.shadowRadius = 3
        ring.shadowOffset = .zero

        for (layer, color, width) in [
            (trailOutline, UIColor.black.withAlphaComponent(0.35), CGFloat(7)),
            (trail, UIColor.systemYellow, CGFloat(4)),
        ] {
            layer.fillColor = nil
            layer.strokeColor = color.cgColor
            layer.lineWidth = width
            layer.lineCap = .round
            layer.lineJoin = .round
        }

        tag.text = "#\(number)"
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.layer.addSublayer(trailOutline)
        canvas.layer.addSublayer(trail)
        canvas.layer.addSublayer(ring)
        canvas.addSubview(tag)
        CATransaction.commit()
        move(to: point)
    }

    func move(to point: CGPoint) {
        if points.count < Self.maxPoints {
            points.append(point)
        } else {
            points[points.count - 1] = point
        }
        let path = UIBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.position = point
        trail.path = path.cgPath
        trailOutline.path = path.cgPath
        CATransaction.commit()
        placeTag()
    }

    /// Names a gesture that took the finger, crossed out with ✕ once
    /// it is cancelled.
    func mark(_ name: String, cancelled: Bool) {
        let label = cancelled ? name + " ✕" : name
        if let index = takers.firstIndex(where: { $0 == name || $0 == name + " ✕" }) {
            takers[index] = label
        } else {
            takers.append(label)
        }
        tag.text = (["#\(number)"] + takers).joined(separator: " · ")
        placeTag()
    }

    func finish(cancelled: Bool, completion: @escaping @MainActor () -> Void) {
        let duration: TimeInterval = cancelled ? 1.2 : 0.8
        if cancelled {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ring.strokeColor = UIColor.systemRed.cgColor
            ring.fillColor = UIColor.systemRed.withAlphaComponent(0.3).cgColor
            CATransaction.commit()
            tag.text = (tag.text ?? "") + " · cancelled"
            placeTag()
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                self?.remove()
                completion()
            }
        }
        ring.opacity = 0
        ring.transform = CATransform3DMakeScale(0.5, 0.5, 1)
        trail.opacity = 0
        trailOutline.opacity = 0
        CATransaction.commit()
        UIView.animate(withDuration: duration) { [tag] in
            tag.alpha = 0
        }
    }

    private func remove() {
        ring.removeFromSuperlayer()
        trail.removeFromSuperlayer()
        trailOutline.removeFromSuperlayer()
        tag.removeFromSuperview()
    }

    /// Above the finger, where it stays readable, and inside the screen.
    private func placeTag() {
        guard let canvas, let point = points.last else {
            return
        }
        tag.sizeToFit()
        let size = tag.bounds.size
        let bounds = canvas.bounds.insetBy(dx: 4, dy: 4)
        var center = CGPoint(x: point.x, y: point.y - Self.radius - 6 - size.height / 2)
        center.x = min(max(center.x, bounds.minX + size.width / 2), bounds.maxX - size.width / 2)
        center.y = max(center.y, bounds.minY + size.height / 2)
        tag.center = center
    }
}

private final class TagLabel: UILabel {
    private let insets = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        textColor = .white
        backgroundColor = UIColor.black.withAlphaComponent(0.7)
        layer.cornerRadius = 6
        layer.masksToBounds = true
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let fitting = super.sizeThatFits(size)
        return CGSize(
            width: fitting.width + insets.left + insets.right,
            height: fitting.height + insets.top + insets.bottom
        )
    }
}

// MARK: - Log file

/// Appends log lines to a file off the main thread, so writing never
/// delays a frame. Starts the file over when created.
private final class LogFile: @unchecked Sendable {
    private let queue = DispatchQueue(label: "TouchInspector.log", qos: .utility)
    private var handle: FileHandle?
    private var written = 0
    private static let limit = 8_000_000

    init(url: URL) {
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        handle = try? FileHandle(forWritingTo: url)
    }

    func write(_ line: String) {
        queue.async { [self] in
            guard let handle, written < Self.limit else {
                return
            }
            let data = Data((line + "\n").utf8)
            try? handle.write(contentsOf: data)
            written += data.count
        }
    }

    func close() {
        queue.async { [self] in
            try? handle?.close()
            handle = nil
        }
    }
}

#endif
