import CoreGraphics
import Foundation
import XCTest

@testable import RibbonCore

final class RibbonCoreTests: XCTestCase {
  func testWidthPolicyDefaultsMigratesAndReachesEngine() throws {
    let legacy = try JSONDecoder().decode(RibbonSettings.self, from: Data("{}".utf8))
    XCTAssertEqual(legacy.widthPolicy, .preserve)
    XCTAssertTrue(try legacy.engineConfiguration().contains("fill_available_width = false"))
    var settings = legacy
    settings.widthPolicy = .fill
    let restored = try JSONDecoder().decode(
      RibbonSettings.self, from: JSONEncoder().encode(settings))
    XCTAssertEqual(restored.widthPolicy, .fill)
    XCTAssertTrue(try restored.engineConfiguration().contains("fill_available_width = true"))
    XCTAssertThrowsError(
      try JSONDecoder().decode(
        RibbonSettings.self, from: Data(#"{"widthPolicy":"unknown"}"#.utf8)))
  }
  func testEngineWireStateDecodesWithStableFieldNames() throws {
    let wire = Data(
      #"{"version":1,"active":{"focused_window_id":23},"virtual_workspaces":[{"windows":[{"window_id":23,"bundle_id":"dev.ribbon.fixture","floating":false}]}]}"#
        .utf8)
    let state = try JSONDecoder().decode(EngineState.self, from: wire)
    XCTAssertEqual(state.active.focusedWindowID, 23)
    XCTAssertEqual(state.windows.first?.windowID, 23)
    XCTAssertEqual(state.windows.first?.bundleID, RibbonSettings.fixtureBundleID)
  }
  func testAutomaticScopeIncludesNewAppsAndHonorsExactExclusions() throws {
    var settings = RibbonSettings()
    XCTAssertEqual(settings.scope, .all)
    XCTAssertTrue(settings.canManageApplications)
    XCTAssertTrue(settings.manages("com.apple.Safari"))
    XCTAssertTrue(settings.manages("com.example.NewlyLaunched"))
    settings.excludedBundleIDs = ["com.apple.Safari"]
    XCTAssertFalse(settings.manages("com.apple.Safari"))
    XCTAssertTrue(settings.manages("com.apple.Safari.Other"))
    XCTAssertFalse(settings.manages(RibbonSettings.appBundleID))
    XCTAssertFalse(settings.manages("com.apple.systempreferences"))
    XCTAssertEqual(settings.engineScopeEnvironment["RIBBON_MANAGEMENT_SCOPE"], "all")
    XCTAssertEqual(settings.engineScopeEnvironment["RIBBON_EXCLUDED_APPS"], "com.apple.Safari")
    let restored = try JSONDecoder().decode(
      RibbonSettings.self, from: JSONEncoder().encode(settings))
    XCTAssertEqual(restored, settings)
  }

  func testExplicitAndDemoScopesCannotExpandToOtherApplications() throws {
    var settings = RibbonSettings()
    settings.scope = .demo
    XCTAssertEqual(
      settings.managedBundleIDs(in: [RibbonSettings.fixtureBundleID, "com.apple.Safari"]),
      [RibbonSettings.fixtureBundleID])
    XCTAssertEqual(settings.engineScopeEnvironment["RIBBON_MANAGEMENT_SCOPE"], "selected")
    XCTAssertEqual(
      settings.engineScopeEnvironment["RIBBON_MANAGED_APPS"], RibbonSettings.fixtureBundleID)
    settings.scope = .selected
    XCTAssertFalse(settings.canManageApplications)
    settings.selectedBundleIDs = ["com.apple.Safari", RibbonSettings.appBundleID, "*"]
    XCTAssertEqual(settings.managedBundleIDs(in: settings.selectedBundleIDs), ["com.apple.Safari"])
    XCTAssertThrowsError(try settings.validated())
    settings.selectedBundleIDs = []
    settings.excludedBundleIDs = ["*"]
    XCTAssertThrowsError(try settings.validated())
  }

  func testAutomaticRecoveryCoversNewApplicationsButNeverExcludedOnes() throws {
    let journal = try RecoveryJournal(
      windows: [], scope: .all,
      excludedBundleIDs: ["com.example.Ignored"]
    ).validated()
    XCTAssertEqual(journal.version, 2)
    let restored = try JSONDecoder().decode(
      RecoveryJournal.self, from: JSONEncoder().encode(journal)
    ).validated()
    XCTAssertEqual(
      restored.recoveryBundleIDs(in: [
        "com.example.New", "com.example.Ignored",
        RibbonSettings.appBundleID, "com.apple.systempreferences",
      ]), ["com.example.New"])
    let old = try RecoveryJournal(windows: [], managedBundleIDs: ["com.example.Original"])
      .validated()
    XCTAssertEqual(old.recoveryBundleIDs(in: ["com.example.New"]), ["com.example.Original"])
    var data = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
    data.removeValue(forKey: "scope")
    data.removeValue(forKey: "excludedBundleIDs")
    let legacy = try JSONDecoder().decode(
      RecoveryJournal.self,
      from: JSONSerialization.data(withJSONObject: data)
    ).validated()
    XCTAssertEqual(legacy.scope, .selected)
    XCTAssertEqual(legacy.recoveryBundleIDs(in: ["com.example.New"]), ["com.example.Original"])
  }

  func testInvalidPersistedSettingsCannotBecomeEngineConfiguration() throws {
    var settings = RibbonSettings()
    settings.gap = -1
    XCTAssertThrowsError(try settings.engineConfiguration())
    settings = RibbonSettings()
    settings.gestureFingers = 2
    XCTAssertThrowsError(try settings.validated())
  }

  func testRecoveryRejectsReusedProcessIDsAndInvalidGeometry() throws {
    let window = SavedWindow(
      pid: 123, bundleID: "com.example.App", launchTime: 100, windowID: 8,
      frame: WindowFrame(CGRect(x: -300, y: 20, width: 600, height: 400)))
    XCTAssertTrue(window.belongs(toPID: 123, bundle: "com.example.App", launchedAt: 100))
    XCTAssertFalse(window.belongs(toPID: 123, bundle: "com.example.App", launchedAt: 101))
    XCTAssertFalse(window.belongs(toPID: 123, bundle: "com.example.Other", launchedAt: 100))
    XCTAssertNoThrow(try RecoveryJournal(windows: [window]).validated())
    let bad = SavedWindow(
      pid: 123, bundleID: "com.example.App", launchTime: 100, windowID: 8,
      frame: WindowFrame(CGRect(x: 0, y: 0, width: 0, height: 1)))
    XCTAssertThrowsError(try RecoveryJournal(windows: [bad]).validated())
    XCTAssertThrowsError(
      try RecoveryJournal(windows: [window], managedBundleIDs: ["com.example.Other"]).validated())
    XCTAssertThrowsError(
      try RecoveryJournal(windows: [], managedBundleIDs: [RibbonSettings.appBundleID]).validated())
  }

  func testAtomicStorePreservesUnreadableJournalForRecovery() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LocalStore(directory: directory)
    try store.write(RecoveryJournal(windows: []), to: "recovery.json")
    let stored = try XCTUnwrap(store.read(RecoveryJournal.self, from: "recovery.json"))
    XCTAssertEqual(stored.version, 1)
    let permissions = try FileManager.default.attributesOfItem(
      atPath: directory.appendingPathComponent("recovery.json").path)
    XCTAssertEqual((permissions[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    let corrupt = Data("broken recovery".utf8)
    try corrupt.write(to: directory.appendingPathComponent("recovery.json"))
    XCTAssertThrowsError(try store.read(RecoveryJournal.self, from: "recovery.json"))
    XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("recovery.json")), corrupt)
  }

  func testContinuousOutputTimesOutWithoutPipeDeadlock() async throws {
    do {
      _ = try await CommandRunner().run(
        URL(fileURLWithPath: "/usr/bin/yes"), arguments: ["test"], timeout: 0.1)
      XCTFail("A continuous command should time out")
    } catch CommandError.timedOut {}
  }

  func testTimeoutIsBoundedAndFollowingCommandStillWorks() async throws {
    let runner = CommandRunner()
    let start = Date()
    do {
      _ = try await runner.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 0.1)
      XCTFail("Expected timeout")
    } catch CommandError.timedOut {}
    XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    let next = try await runner.run(URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["ready"])
    XCTAssertEqual(next.status, 0)
    XCTAssertEqual(next.output, "ready")
  }
}
