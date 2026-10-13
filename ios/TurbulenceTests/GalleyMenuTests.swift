import XCTest
@testable import Turbulence

/// The galley main menu's layout and turbulence springs (GDD §9a; specs/galley-main-menu).
final class GalleyMenuTests: XCTestCase {
    /// Landscape screens from the smallest iPhone to the largest iPad, in points.
    private let screens = [CGSize(width: 667, height: 375), CGSize(width: 874, height: 402),
                           CGSize(width: 956, height: 440), CGSize(width: 1366, height: 1024)]

    func testTheFourButtonsAreBigEnoughSeparateAndOnScreen() {
        for size in screens {
            let rects = GalleyLayout.buttons.map { GalleyLayout.tapRect($0, in: size) }
            let screen = CGRect(origin: .zero, size: size)
            for (i, r) in rects.enumerated() {
                XCTAssertGreaterThanOrEqual(r.width, 44, "\(GalleyLayout.buttons[i]) on \(size)")
                XCTAssertGreaterThanOrEqual(r.height, 44, "\(GalleyLayout.buttons[i]) on \(size)")
                XCTAssertTrue(screen.contains(r), "\(GalleyLayout.buttons[i]) runs off \(size)")
                for other in rects[(i + 1)...] { XCTAssertFalse(r.intersects(other), "buttons overlap on \(size)") }
            }
        }
    }

    func testTheSafeAreaAlwaysShowsAndThePhoneHasNoGaps() {
        for size in screens {
            let p = GalleyLayout.placement(in: size)
            let safe = p.rect(GalleyLayout.safe)
            XCTAssertTrue(CGRect(origin: .zero, size: size).insetBy(dx: -0.5, dy: -0.5).contains(safe), "safe area cropped on \(size)")
        }
        // on a phone the wall covers the whole screen
        let phone = CGSize(width: 874, height: 402)
        XCTAssertTrue(GalleyLayout.placement(in: phone).wallRect.insetBy(dx: -0.5, dy: -0.5)
            .contains(CGRect(origin: .zero, size: phone)))
    }

    func testAFullKickPeaksAtTheAmplitudeAndSettles() {
        let kick = [GalleyKick(time: 0, strength: 1, sign: 1)]
        for sway in GalleyMotion.all {
            let samples = stride(from: 0.0, through: sway.settle * 2, by: 0.002).map { sway.value(at: $0 + sway.delay, kicks: kick) }
            XCTAssertEqual(samples.max()!, sway.amplitude, accuracy: sway.amplitude * 0.02)
            XCTAssertLessThan(abs(sway.value(at: sway.settle + sway.delay, kicks: kick)), sway.amplitude * 0.03)
            XCTAssertTrue(sway.isResting(at: sway.settle * 1.6, kicks: kick))
        }
    }

    func testKicksAddUpButNeverPastTheLimit() {
        let sway = GalleyMotion.tag
        let one = [GalleyKick(time: 0, strength: 1, sign: 1)]
        let two = one + [GalleyKick(time: 1 / sway.frequency, strength: 1, sign: 1)]     // in step: they add up
        let peak = { (k: [GalleyKick]) in stride(from: 0.0, through: 4, by: 0.002).map { abs(sway.value(at: $0, kicks: k)) }.max()! }
        XCTAssertGreaterThan(peak(two), peak(one))
        XCTAssertLessThanOrEqual(peak(two), sway.limit!)
        let many = (0..<10).map { GalleyKick(time: Double($0) / sway.frequency, strength: 1, sign: 1) }
        XCTAssertLessThanOrEqual(peak(many), sway.amplitude * 1.5)
    }

    func testNoKicksNoMotion() {
        for sway in GalleyMotion.all { XCTAssertEqual(sway.value(at: 3, kicks: []), 0) }
    }
}
