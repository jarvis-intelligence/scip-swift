import Foundation
import IndexStoreDB
import Testing

@testable import scip_swift

/// Requirement: exact end used when present, today's approximation byte-identical when nil
/// (RANGE-03 fallback contract) — pure-unit over IndexStoreDB SymbolLocations.
@Suite("PositionMapping")
struct PositionMappingTests {
  private func makeLocation(line: Int, utf8Column: Int) -> SymbolLocation {
    SymbolLocation(
      path: "/fake/path.swift",
      timestamp: Date(),
      moduleName: "FakeModule",
      line: line,
      utf8Column: utf8Column
    )
  }

  @Test("1-based anchor converts to 0-based line and start character")
  func zeroBasedMath() {
    let range = PositionMapping.singleLineRange(
      location: makeLocation(line: 4, utf8Column: 29),
      displayName: "String"
    )
    #expect(range.line == 3)
    #expect(range.startCharacter == 28)
  }

  @Test("exact end column is used verbatim when present")
  func exactEndUsedWhenPresent() {
    // F3a: getter:name anchored at token `name` [13,17); the display-name approximation would
    // produce 24 (+7 drift). With the exact end supplied the range must carry 17.
    let range = PositionMapping.singleLineRange(
      location: makeLocation(line: 2, utf8Column: 14),
      displayName: "getter:name",
      exactEndColumn: 17
    )
    #expect(range.line == 1)
    #expect(range.startCharacter == 13)
    #expect(range.endCharacter == 17)
    #expect(range.endCharacter != 24)
  }

  @Test("nil exact end keeps today's approximation byte-for-byte")
  func approximationWhenNil() {
    let cases: [(displayName: String, start: Int32, expectedEnd: Int32)] = [
      ("getter:name", 13, 24),
      ("getter:名前", 4, 17),
      ("greet(name:)", 5, 10),
      ("String", 17, 23),
      ("emoji", 4, 9),
    ]
    for testCase in cases {
      let range = PositionMapping.singleLineRange(
        location: makeLocation(line: 1, utf8Column: Int(testCase.start) + 1),
        displayName: testCase.displayName,
        exactEndColumn: nil
      )
      #expect(range.startCharacter == testCase.start)
      #expect(range.endCharacter == testCase.expectedEnd)
    }
  }

  @Test("approximation handles compound names via prefix-before-paren")
  func compoundNameApproximation() {
    let range = PositionMapping.singleLineRange(
      location: makeLocation(line: 1, utf8Column: 6),
      displayName: "greet(name:)"
    )
    #expect(range.startCharacter == 5)
    #expect(range.endCharacter == 10)
  }

  @Test("invalid zero/one-based inputs clamp to non-negative values")
  func clamping() {
    let range = PositionMapping.singleLineRange(
      location: makeLocation(line: 0, utf8Column: 0),
      displayName: ""
    )
    #expect(range.line == 0)
    #expect(range.startCharacter == 0)
    #expect(range.endCharacter == 0)
  }
}
