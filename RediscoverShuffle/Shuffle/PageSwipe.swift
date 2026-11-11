import Foundation

/// The rules for swiping a playlist page back: which touches are swipes
/// back, where the page sits under the finger, and whether letting go takes
/// it back. Distances are in points and speeds in points per second, both
/// measured toward the trailing edge, so they read the same in
/// right-to-left layouts.
enum PageSwipe {
    enum Sorting: Equatable {
        /// The finger hasn't gone far enough to tell.
        case undecided
        case swipeBack
        /// A scroll, or a swipe toward the leading edge.
        case other
    }

    /// How far the finger travels before a touch is sorted.
    static let sortingDistance: CGFloat = 10
    /// A touch that sets off more steeply than this is a scroll. Sorting on
    /// both directions, not on the distance travelled, keeps a quick
    /// vertical flick from passing for a swipe back before it has gone far
    /// enough to look like a scroll.
    static let steepestSlope: CGFloat = 0.5
    /// A flick toward the trailing edge goes back from any distance past a
    /// small one, and a flick toward the leading edge stays.
    static let flickSpeed: CGFloat = 300
    static let flickDistance: CGFloat = 16
    /// An unhurried swipe goes back once it has passed this much of the
    /// width.
    static let goingBackFraction: CGFloat = 1 / 3
    /// How small the page gets under the finger, and over what share of
    /// the width it gets there.
    static let smallestScale: CGFloat = 0.8
    static let shrinkingFraction: CGFloat = 0.4
    /// Toward the leading edge the page holds back this much.
    static let leadingResistance: CGFloat = 0.2
    /// How long a page takes to come under the finger that takes it: at
    /// rest, where the finger has only gone the few points it took to sort
    /// the touch, and at half its size or smaller, mid-flight.
    static let quickestCatchUp: Double = 0.09
    static let slowestCatchUp: Double = 0.26

    /// Sorts a touch that has moved `distance` toward the trailing edge
    /// and `rise` up or down since it landed. A finger that caught a page
    /// on its way back holds the page itself, with nothing under it to
    /// scroll or press, so the page goes with it whichever way it sets off.
    static func sorting(distance: CGFloat, rise: CGFloat, holdsPage: Bool = false) -> Sorting {
        let rise = abs(rise)
        guard max(abs(distance), rise) >= sortingDistance else {
            return .undecided
        }
        if holdsPage {
            return .swipeBack
        }
        return distance > 0 && rise <= distance * steepestSlope ? .swipeBack : .other
    }

    /// How long a page showing `shownWidth` wide, of its full `width`,
    /// takes to come under the finger. The further it has to grow, the
    /// longer it takes, so a page taken mid-flight doesn't snap to size.
    static func catchUpDuration(shownWidth: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else {
            return quickestCatchUp
        }
        let missing = min(max(1 - shownWidth / width, 0) / 0.5, 1)
        return quickestCatchUp + (slowestCatchUp - quickestCatchUp) * Double(missing)
    }

    /// Whether a swipe that lets go `distance` from where it landed, moving
    /// at `speed`, takes a page `width` wide back.
    static func goesBack(distance: CGFloat, speed: CGFloat, width: CGFloat) -> Bool {
        if speed >= flickSpeed {
            return distance >= flickDistance
        }
        return width > 0 && distance >= width * goingBackFraction && speed > -flickSpeed
    }

    /// How much the page has shrunk once the finger has gone `distance`.
    static func scale(distance: CGFloat, width: CGFloat) -> CGFloat {
        let shrink = min(max(distance, 0) / (max(width, 1) * shrinkingFraction), 1)
        return 1 - (1 - smallestScale) * shrink
    }

    /// Where a page that rests at `page` sits under a finger that landed
    /// at `grip` and has since moved `translation`, `distance` of it
    /// toward the trailing edge. The page shrinks around the finger, so the
    /// finger keeps hold of the spot it landed on.
    static func cardFrame(page: CGRect, grip: CGPoint, translation: CGPoint, distance: CGFloat) -> CGRect {
        // Foundation alone gives a rectangle its origin and size, not its
        // edges.
        let scale = scale(distance: distance, width: page.size.width)
        let moved = distance >= 0 ? translation.x : translation.x * leadingResistance
        let x: CGFloat = grip.x + moved - (grip.x - page.origin.x) * scale
        let y: CGFloat = grip.y + translation.y - (grip.y - page.origin.y) * scale
        return CGRect(
            origin: CGPoint(x: x, y: y),
            size: CGSize(width: page.size.width * scale, height: page.size.height * scale)
        )
    }
}
