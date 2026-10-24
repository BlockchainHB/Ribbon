import CoreGraphics
import XCTest

@testable import Ribbon

final class RecoveryTargetTests: XCTestCase {
  func testAlreadyRestoredOversizedMinimumIsNotSqueezedAgain() {
    let display = CGRect(x: 0, y: 30, width: 2560, height: 1301)
    let saved = CGRect(x: 0, y: 719, width: 2760, height: 452)
    XCTAssertEqual(
      AccessibilityWorkspace.recoveryTarget(saved: saved, current: saved, displays: [display]),
      saved)
  }

  func testMatchingOriginalOnDisconnectedDisplayStillRecoversVisibility() {
    let remaining = CGRect(x: 0, y: 30, width: 2560, height: 1301)
    let saved = CGRect(x: 2560, y: 828, width: 1928, height: 452)
    let target = AccessibilityWorkspace.recoveryTarget(
      saved: saved, current: saved, displays: [remaining])
    XCTAssertTrue(remaining.contains(target))
    XCTAssertNotEqual(target.origin, saved.origin)
  }

  func testUnrestoredAndNewWindowsRetainExistingFitPolicy() {
    let display = CGRect(x: 0, y: 30, width: 2560, height: 1301)
    let outside = CGRect(x: 2400, y: 1200, width: 560, height: 452)
    let current = CGRect(x: 100, y: 100, width: 800, height: 800)
    XCTAssertTrue(
      display.contains(
        AccessibilityWorkspace.recoveryTarget(
          saved: outside, current: current, displays: [display])))
    XCTAssertTrue(
      display.contains(
        AccessibilityWorkspace.recoveryTarget(saved: nil, current: outside, displays: [display])))
  }

  func testMatchingNormalWindowStillFitsInsideUsableBounds() {
    let display = CGRect(x: 0, y: 30, width: 2560, height: 1301)
    let saved = CGRect(x: 2300, y: 500, width: 400, height: 452)
    let target = AccessibilityWorkspace.recoveryTarget(
      saved: saved, current: saved, displays: [display])
    XCTAssertTrue(display.contains(target))
    XCTAssertNotEqual(target.origin, saved.origin)
  }
}
