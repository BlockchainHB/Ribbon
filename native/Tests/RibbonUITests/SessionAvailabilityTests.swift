import XCTest

@testable import Ribbon

final class SessionAvailabilityTests: XCTestCase {
  func testRunningSessionCanAlwaysBePausedDespiteItsRecoveryJournal() {
    for recover in [false, true] {
      for scope in [false, true] {
        XCTAssertTrue(
          SessionPhase.running.canToggleSession(
            recoveryPending: recover, canManageApplications: scope))
      }
    }
  }

  func testStoppedAndTransitioningSessionsEnforceStartGuards() {
    XCTAssertTrue(
      SessionPhase.stopped.canToggleSession(recoveryPending: false, canManageApplications: true))
    XCTAssertFalse(
      SessionPhase.stopped.canToggleSession(recoveryPending: true, canManageApplications: true))
    XCTAssertFalse(
      SessionPhase.stopped.canToggleSession(recoveryPending: false, canManageApplications: false))
    for phase: SessionPhase in [.starting, .stopping] {
      XCTAssertFalse(phase.canToggleSession(recoveryPending: false, canManageApplications: true))
      XCTAssertFalse(phase.canToggleSession(recoveryPending: true, canManageApplications: true))
    }
  }
}
