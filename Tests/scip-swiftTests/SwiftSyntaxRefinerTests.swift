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

  @Test("single doc piece yields its text with the marker stripped")
  func singlePieceDoc() throws {
    let source = """
      /// Single piece.
      public func singlePiece() {}
      """
    let refiner = try makeRefiner(source: source)
    #expect(refiner.documentation(line: 2, utf8Column: 13) == "Single piece.")
  }

  @Test("consecutive doc pieces join with newlines in reading order")
  func multiPieceDocJoinsWithNewlines() throws {
    let source = """
      /// First line.
      /// Second line.
      public func dualDoc() {}
      """
    let refiner = try makeRefiner(source: source)
    #expect(refiner.documentation(line: 3, utf8Column: 13) == "First line.\nSecond line.")
  }

  @Test("bare doc marker yields an empty line preserving the paragraph break")
  func bareMarkerPreservesParagraphBreak() throws {
    let source = """
      /// Paragraph one.
      ///
      /// Paragraph two.
      public func twoParagraphs() {}
      """
    let refiner = try makeRefiner(source: source)
    #expect(refiner.documentation(line: 4, utf8Column: 13) == "Paragraph one.\n\nParagraph two.")
  }

  @Test("asterisk block doc strips wrappers, per-line asterisks, and artifact lines")
  func asteriskBlockDoc() throws {
    let source = """
      /**
       * Block line one.
       * - parameter x: an int
       *
       * Block line two.
       */
      public func blocky(x: Int) {}
      """
    let refiner = try makeRefiner(source: source)
    #expect(
      refiner.documentation(line: 7, utf8Column: 13)
        == "Block line one.\n- parameter x: an int\n\nBlock line two."
    )
  }

  @Test("plain block doc keeps the blank interior line as a paragraph break")
  func plainBlockDoc() throws {
    let source = """
      /**
       Block doc first.
       - parameter x: an int

       Second paragraph.
       */
      public func plainBlock(x: Int) {}
      """
    let refiner = try makeRefiner(source: source)
    #expect(
      refiner.documentation(line: 7, utf8Column: 13)
        == "Block doc first.\n- parameter x: an int\n\nSecond paragraph."
    )
  }

  @Test("four-slash divider line is dropped entirely")
  func fourSlashDividerDropped() throws {
    let source = """
      //// SECTIONMARKER divider

      /// Real doc.
      public func realDoc() {}
      """
    let refiner = try makeRefiner(source: source)
    #expect(refiner.documentation(line: 4, utf8Column: 13) == "Real doc.")
  }

  @Test("plain comment between doc pieces contributes nothing")
  func interleavedPlainCommentExcluded() throws {
    let source = """
      /// First line.
      // interleaved MARKER noise
      /// Second line.
      public func dual() {}
      """
    let refiner = try makeRefiner(source: source)
    #expect(refiner.documentation(line: 4, utf8Column: 13) == "First line.\nSecond line.")
  }

  @Test("license header above an import produces no map entries")
  func licenseHeaderExcluded() throws {
    let source = """
      // License line one with MARKER.
      // License line two.

      import Foundation

      /// Documented after the header.
      public func afterHeader() {}
      """
    let refiner = try makeRefiner(source: source)
    #expect(refiner.documentation(line: 4, utf8Column: 1) == nil, "import anchor must not hit")
    #expect(refiner.documentation(line: 7, utf8Column: 13) == "Documented after the header.")
  }

  @Test("trailing comment after a statement never appears")
  func trailingCommentExcluded() throws {
    let source = """
      /// Documented value.
      public var trailed = 1 // trailing MARKER noise

      public func untouched() {}
      """
    let refiner = try makeRefiner(source: source)
    #expect(refiner.documentation(line: 2, utf8Column: 12) == "Documented value.")
  }

  @Test("plain comment between doc and decl keeps the doc")
  func plainCommentBetweenDocAndDecl() throws {
    let source = """
      /// Kept doc.
      // plain between
      public func keptDoc() {}
      """
    let refiner = try makeRefiner(source: source)
    #expect(refiner.documentation(line: 3, utf8Column: 13) == "Kept doc.")
  }

  @Test("attribute between doc and decl still documents via the name token")
  func attributedDeclKeysAtNameToken() throws {
    let source = """
      /// Documented compute.
      @inline(__always)
      public func compute(_ x: Int) -> Int { x }
      """
    let refiner = try makeRefiner(source: source)
    #expect(refiner.documentation(line: 3, utf8Column: 13) == "Documented compute.")
    #expect(
      refiner.documentation(line: 2, utf8Column: 1) == nil,
      "first-token keying would have landed the doc on the attribute's @"
    )
  }

  @Test("var and let key at the binding identifier")
  func varAndLetKeyAtBindingIdentifier() throws {
    let source = """
      /// Stored value.
      public var stored: Int = 0

      /// Frozen constant.
      public let frozen = 41
      """
    let refiner = try makeRefiner(source: source)
    #expect(refiner.documentation(line: 2, utf8Column: 12) == "Stored value.")
    #expect(refiner.documentation(line: 5, utf8Column: 12) == "Frozen constant.")
  }

  @Test("struct, init, and deinit key at their verified anchors")
  func structInitDeinitAnchors() throws {
    let source = """
      /// A thing.
      public struct Thing {
        /// Makes a thing.
        public init() {}

        /// Tears down.
        deinit {}
      }
      """
    let refiner = try makeRefiner(source: source)
    #expect(refiner.documentation(line: 2, utf8Column: 15) == "A thing.")
    #expect(refiner.documentation(line: 4, utf8Column: 10) == "Makes a thing.")
    #expect(refiner.documentation(line: 7, utf8Column: 3) == "Tears down.")
  }

  @Test("extension keys at the extended type's first token")
  func extensionKeysAtExtendedType() throws {
    let source = """
      /// Extends Thing.
      extension Thing {
        public func helper() {}
      }
      """
    let refiner = try makeRefiner(source: source)
    #expect(refiner.documentation(line: 2, utf8Column: 11) == "Extends Thing.")
  }

  @Test("multi-element enum cases share one doc")
  func multiElementEnumCasesShareDoc() throws {
    let source = """
      /// Color cases.
      public enum Color {
        /// Primary hues.
        case red, blue
      }
      """
    let refiner = try makeRefiner(source: source)
    #expect(refiner.documentation(line: 2, utf8Column: 13) == "Color cases.")
    #expect(refiner.documentation(line: 4, utf8Column: 8) == "Primary hues.")
    #expect(refiner.documentation(line: 4, utf8Column: 13) == "Primary hues.")
  }

  @Test("undocumented decl anchor returns nil; invalid coordinates return nil")
  func lookupContractNilOnMiss() throws {
    let source = """
      public func noDoc() {}
      """
    let refiner = try makeRefiner(source: source)
    #expect(refiner.documentation(line: 1, utf8Column: 13) == nil)
    #expect(refiner.documentation(line: 0, utf8Column: 1) == nil)
    #expect(refiner.documentation(line: 1, utf8Column: 0) == nil)
    #expect(refiner.documentation(line: 99, utf8Column: 1) == nil)
  }

  @Test("constructing one refiner records exactly one parse for its file")
  func parseCountRecordsExactlyOneParse() throws {
    let directory = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("scip-swift-refiner-parse-count-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let path = (directory as NSString).appendingPathComponent("Parsed.swift")
    try "public func hookTarget() {}\n".write(toFile: path, atomically: true, encoding: .utf8)

    _ = try #require(SwiftSyntaxRefiner(filePath: path))

    #expect(SwiftSyntaxRefiner.parseCount(forFilePath: path) == 1)
  }
}
