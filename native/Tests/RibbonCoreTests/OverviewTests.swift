import Foundation
import XCTest

@testable import RibbonCore

final class OverviewTests: XCTestCase {
  func testOverviewPreservesEngineOrderAndStackMembershipAcrossDisplays() throws {
    let data = Data(
      #"{"focused":9,"displays":[{"id":1,"active":true,"workspaces":[{"active":true,"columns":[{"kind":"stack","selected":1,"windows":[{"id":8,"app_name":"Notes","bundle_id":"com.apple.Notes","title":"First"},{"id":9,"app_name":"Notes","bundle_id":"com.apple.Notes","title":"Second"}]}]},{"active":false,"columns":[{"kind":"single","selected":0,"windows":[{"id":99,"app_name":"Notes","bundle_id":"com.apple.Notes","title":"Another Space"}]}]}]},{"id":2,"active":false,"workspaces":[{"active":true,"columns":[{"kind":"single","selected":0,"windows":[{"id":11,"app_name":"Safari","bundle_id":"com.apple.Safari","title":"Browser"}]}]}]}]}"#
        .utf8)
    let state = try JSONDecoder().decode(OverviewSnapshot.self, from: data)
    XCTAssertEqual(state.focused, 9)
    XCTAssertEqual(state.displays[0].columns.map(\.id), [9])
    XCTAssertEqual(state.displays[0].columns[0].windows.map(\.id), [8, 9])
    XCTAssertEqual(state.displays[1].columns.map(\.id), [11])
    XCTAssertEqual(state.columns(containing: 8)?.first?.id, 9)
    XCTAssertNil(
      state.columns(containing: 99), "Other native Spaces must not appear in the overview.")
  }
  func testPairMembershipComesFromEngineAndDefinesMovementBlocks() throws {
    let data = Data(
      #"{"focused":1,"displays":[{"id":1,"active":true,"workspaces":[{"active":true,"columns":[{"kind":"single","pair_id":4294967001,"selected":0,"windows":[{"id":1,"app_name":"A","bundle_id":"a","title":"A"}]},{"kind":"single","pair_id":4294967001,"selected":0,"windows":[{"id":2,"app_name":"B","bundle_id":"b","title":"B"}]},{"kind":"single","selected":0,"windows":[{"id":3,"app_name":"C","bundle_id":"c","title":"C"}]}]}]}]}"#
        .utf8)
    let state = try JSONDecoder().decode(OverviewSnapshot.self, from: data)
    XCTAssertEqual(state.displays[0].columns[0].pairID, 4_294_967_001)
    XCTAssertEqual(state.movementRange(containing: 1), 0..<2)
    XCTAssertEqual(state.movementRange(containing: 2), 0..<2)
    XCTAssertEqual(state.movementRange(containing: 3), 2..<3)
    XCTAssertNil(state.movementRange(containing: 99))
  }

}
