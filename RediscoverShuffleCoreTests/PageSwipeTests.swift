import CoreGraphics
import Foundation
import Testing
@testable import RediscoverShuffleCore

@Suite("Page swipe")
struct PageSwipeTests {
    private let page = CGRect(origin: .zero, size: CGSize(width: 400, height: 800))

    @Test("A touch is sorted once it has travelled far enough")
    func sortingWaitsForDistance() {
        #expect(PageSwipe.sorting(distance: 6, rise: 3) == .undecided)
        #expect(PageSwipe.sorting(distance: -4, rise: -9) == .undecided)
        #expect(PageSwipe.sorting(distance: 10, rise: 0) == .swipeBack)
    }

    @Test("A swipe toward the trailing edge is a swipe back whether it drifts up or down")
    func levelSwipesGoBack() {
        #expect(PageSwipe.sorting(distance: 12, rise: -5) == .swipeBack)
        #expect(PageSwipe.sorting(distance: 12, rise: 5) == .swipeBack)
        #expect(PageSwipe.sorting(distance: 40, rise: 20) == .swipeBack)
    }

    @Test("Scrolls and swipes toward the leading edge are left alone")
    func scrollsAreLeftAlone() {
        #expect(PageSwipe.sorting(distance: 4, rise: 12) == .other)
        #expect(PageSwipe.sorting(distance: 12, rise: -7) == .other)
        #expect(PageSwipe.sorting(distance: -14, rise: 1) == .other)
    }

    @Test("A finger holding a caught page moves it whichever way it sets off")
    func heldPagesFollowEveryDirection() {
        #expect(PageSwipe.sorting(distance: 3, rise: 4, holdsPage: true) == .undecided)
        #expect(PageSwipe.sorting(distance: 2, rise: -12, holdsPage: true) == .swipeBack)
        #expect(PageSwipe.sorting(distance: -11, rise: 0, holdsPage: true) == .swipeBack)
        #expect(PageSwipe.sorting(distance: 12, rise: 3, holdsPage: true) == .swipeBack)
    }

    @Test("A page taken mid-flight takes longer to come under the finger the smaller it is")
    func catchUpGrowsWithTheGap() {
        #expect(PageSwipe.catchUpDuration(shownWidth: 400, width: 400) == PageSwipe.quickestCatchUp)
        #expect(PageSwipe.catchUpDuration(shownWidth: 200, width: 400) == PageSwipe.slowestCatchUp)
        #expect(PageSwipe.catchUpDuration(shownWidth: 60, width: 400) == PageSwipe.slowestCatchUp)
        let halfway = PageSwipe.catchUpDuration(shownWidth: 300, width: 400)
        #expect(halfway > PageSwipe.quickestCatchUp && halfway < PageSwipe.slowestCatchUp)
        #expect(PageSwipe.catchUpDuration(shownWidth: 0, width: 0) == PageSwipe.quickestCatchUp)
    }

    @Test("A flick goes back from a short distance")
    func flicksGoBack() {
        #expect(PageSwipe.goesBack(distance: 20, speed: 900, width: 400))
        #expect(PageSwipe.goesBack(distance: 16, speed: 300, width: 400))
        #expect(!PageSwipe.goesBack(distance: 12, speed: 900, width: 400))
    }

    @Test("An unhurried swipe goes back past a third of the width")
    func slowSwipesGoBackByDistance() {
        #expect(PageSwipe.goesBack(distance: 140, speed: 0, width: 400))
        #expect(PageSwipe.goesBack(distance: 140, speed: 120, width: 400))
        #expect(!PageSwipe.goesBack(distance: 120, speed: 120, width: 400))
        #expect(!PageSwipe.goesBack(distance: 0, speed: 0, width: 400))
    }

    @Test("A flick back toward the leading edge stays, however far the swipe went")
    func flickingBackStays() {
        #expect(!PageSwipe.goesBack(distance: 300, speed: -600, width: 400))
        #expect(PageSwipe.goesBack(distance: 300, speed: -100, width: 400))
    }

    @Test("The page rests in place until the finger moves")
    func cardStartsAtRest() {
        let frame = PageSwipe.cardFrame(
            page: page,
            grip: CGPoint(x: 120, y: 500),
            translation: .zero,
            distance: 0
        )
        #expect(frame == page)
    }

    @Test("The finger keeps hold of the spot it landed on as the page shrinks")
    func fingerKeepsItsSpot() {
        let grip = CGPoint(x: 120, y: 500)
        let translation = CGPoint(x: 80, y: -30)
        let frame = PageSwipe.cardFrame(page: page, grip: grip, translation: translation, distance: 80)
        let scale = frame.size.width / page.size.width

        #expect(scale < 1)
        #expect(abs(frame.size.height / page.size.height - scale) < 0.0001)
        // The spot under the finger, a fraction of the way across the page,
        // is still under the finger.
        let spot = CGPoint(
            x: frame.origin.x + grip.x / page.size.width * frame.size.width,
            y: frame.origin.y + grip.y / page.size.height * frame.size.height
        )
        #expect(abs(spot.x - (grip.x + translation.x)) < 0.0001)
        #expect(abs(spot.y - (grip.y + translation.y)) < 0.0001)
    }

    @Test("The page shrinks steadily, then holds its smallest size")
    func shrinkingLevelsOff() {
        let near = PageSwipe.scale(distance: 40, width: 400)
        let further = PageSwipe.scale(distance: 100, width: 400)
        #expect(near < 1)
        #expect(further < near)
        #expect(PageSwipe.scale(distance: 160, width: 400) == PageSwipe.smallestScale)
        #expect(PageSwipe.scale(distance: 390, width: 400) == PageSwipe.smallestScale)
    }

    @Test("Toward the leading edge the page holds back and keeps its size")
    func leadingEdgeResists() {
        let frame = PageSwipe.cardFrame(
            page: page,
            grip: CGPoint(x: 200, y: 400),
            translation: CGPoint(x: -100, y: 0),
            distance: -100
        )
        #expect(frame.size == page.size)
        #expect(abs(frame.origin.x - -20) < 0.0001)
    }

    @Test("In a right-to-left layout the page follows the finger toward the left")
    func rightToLeftFollowsTheFinger() {
        // The trailing edge is on the left, so a move of -90 is 90 toward it.
        let frame = PageSwipe.cardFrame(
            page: page,
            grip: CGPoint(x: 300, y: 400),
            translation: CGPoint(x: -90, y: 0),
            distance: 90
        )
        #expect(frame.size.width < page.size.width)
        #expect(abs((frame.origin.x + 300 / page.size.width * frame.size.width) - 210) < 0.0001)
    }
}
