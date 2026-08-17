import Foundation
import IndexStoreDB
import SwiftParser
import SwiftSyntax
import Testing

@testable import scip_swift

/// Requirement: exact occurrence end columns via SwiftSyntax token extents (RANGE-01..03) —
/// pure-unit corpus over the F4 Unicode fixture content and error-recovery sources.
@Suite("SwiftSyntaxRefinerTests")
struct SwiftSyntaxRefinerTests {
  private static let unicodeSource = """
    let emoji = "🦖"
    let 名前 = greet(name: "日本語")

    func greet(name: String) -> String {
      "Hello, \\(name) 🎉"
    }
    """

  private static let brokenSource = """
    let ok = 1
    struct Broken { let x: = }
    let alsoOk = 3
    print(ok)
    """

  private func makeRefiner(source: String) throws -> SwiftSyntaxRefiner {
    let directory = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("scip-swift-refiner-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let path = (directory as NSString).appendingPathComponent("Fixture.swift")
    try source.write(toFile: path, atomically: true, encoding: .utf8)
    return try #require(SwiftSyntaxRefiner(filePath: path))
  }

  @Test("exact end equals start plus token UTF-8 byte length, never endPosition")
  func exactExtentInvariant() throws {
    let refiner = try makeRefiner(source: Self.unicodeSource)
    // trailing-trivia regression (F1): `emoji` starts at 0-based col 4, is 5 bytes, and is
    // followed by one space — end must be 9, not endPosition's 10.
    #expect(refiner.exactEndColumn(line: 1, utf8Column: 5) == 9)
    #expect(refiner.exactEndColumn(line: 1, utf8Column: 5) != 10)
  }

  @Test("F4 Unicode rows carry 0-based UTF-8 byte columns")
  func unicodeByteColumns() throws {
    let refiner = try makeRefiner(source: Self.unicodeSource)
    // F4 (1-based IndexStoreDB columns = 0-based + 1):
    // emoji def L1 [4,9); 名前 def L2 [4,10); greet ref L2 [13,18); greet def L4 [5,10);
    // name param def L4 [11,15); String refs L4 [17,23) and [28,34).
    #expect(refiner.exactEndColumn(line: 1, utf8Column: 5) == 9)
    #expect(refiner.exactEndColumn(line: 2, utf8Column: 5) == 10)
    #expect(refiner.exactEndColumn(line: 2, utf8Column: 14) == 18)
    #expect(refiner.exactEndColumn(line: 4, utf8Column: 6) == 10)
    #expect(refiner.exactEndColumn(line: 4, utf8Column: 12) == 15)
    #expect(refiner.exactEndColumn(line: 4, utf8Column: 18) == 23)
    #expect(refiner.exactEndColumn(line: 4, utf8Column: 29) == 34)
  }

  @Test("line and column math round-trips on multi-byte content")
  func lineTableMath() throws {
    // bytes: "let 名前 = greet(...)" — 名前 spans UTF-8 bytes 4..10 of line 2 (1-based col 5,
    // 6 bytes); anchors must be byte deltas rather than UTF-16 units. The bytes after 名前 are
    // space(10), `=`(11), space(12), g(13) — only the `=` is a token start.
    let refiner = try makeRefiner(source: Self.unicodeSource)
    #expect(refiner.exactEndColumn(line: 2, utf8Column: 5) == 10)
    #expect(refiner.exactEndColumn(line: 2, utf8Column: 11) == nil)
    #expect(refiner.exactEndColumn(line: 2, utf8Column: 12) == 12)
    #expect(refiner.exactEndColumn(line: 2, utf8Column: 13) == nil)
    #expect(refiner.exactEndColumn(line: 2, utf8Column: 14) == 18)
  }

  @Test("broken source still yields tokens for valid regions; garbled region misses")
  func errorRecovery() throws {
    let refiner = try makeRefiner(source: Self.brokenSource)
    // F5: ok L1 [4,6); Broken L2 [7,13); alsoOk L3 [4,10); print L4 [0,5); ok ref L4 [6,8).
    // The `x` anchor at L2 col 13 falls inside the garbled region and must miss the map.
    #expect(refiner.exactEndColumn(line: 1, utf8Column: 5) == 6)
    #expect(refiner.exactEndColumn(line: 2, utf8Column: 8) == 13)
    #expect(refiner.exactEndColumn(line: 3, utf8Column: 5) == 10)
    #expect(refiner.exactEndColumn(line: 4, utf8Column: 1) == 5)
    #expect(refiner.exactEndColumn(line: 4, utf8Column: 7) == 8)
    #expect(refiner.exactEndColumn(line: 2, utf8Column: 13) == nil)
  }

  @Test("anchor between token starts returns nil")
  func anchorMissReturnsNil() throws {
    let refiner = try makeRefiner(source: Self.unicodeSource)
    // col 1 of line 1 is `l` of `let`; col 2 is inside the identifier (between real anchors).
    #expect(refiner.exactEndColumn(line: 1, utf8Column: 2) == nil)
    // line 3 is blank — no tokens at all.
    #expect(refiner.exactEndColumn(line: 3, utf8Column: 1) == nil)
    // line beyond EOF.
    #expect(refiner.exactEndColumn(line: 99, utf8Column: 1) == nil)
  }

  @Test("unreadable file yields nil refiner")
  func unreadableFileReturnsNil() {
    let nonexistent = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("scip-swift-refiner-tests-missing-\(UUID().uuidString)")
    #expect(SwiftSyntaxRefiner(filePath: nonexistent) == nil)
  }
}
