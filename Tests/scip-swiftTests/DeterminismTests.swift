import Foundation
import Testing

@testable import scip_swift

/// Requirement: SYM-03 (determinism half) / D-10 — deterministic, cache-safe emission under the
/// canonical symbol format. Two fresh builds of the same index store must be byte-identical;
/// occurrences must follow the Go bindings' canonical ordering/dedup rules ported from
/// `bindings/go/scip` (`sort.go` + `occurrence_range.go` + `canonicalize.go`: ascending by
/// range start, then range end, then symbol string — `Occurrence.Compare` over
/// `Range.CompareStrict` — with stable dedup on (symbol, range, roles)); documents ascend by
/// `relativePath`, `document.symbols` by symbol string; and ToolInfo metadata must be
/// argv-insensitive so CLI double-runs with different `--output` paths stay byte-identical.
@Suite("Determinism")
struct DeterminismTests {

  // MARK: - Fresh double-run (integration; both fixtures, emoji/CJK included)

  @Test(
    "fresh double-run is byte-identical and canonically ordered",
    arguments: DeterminismTests.fixtureCases
  )
  func freshDoubleRunByteIdentity(fixture: FixtureCase) throws {
    let fixtureRepoPath = fixture.path
    let fixtureBuildPath = (fixtureRepoPath as NSString).appendingPathComponent(".build")
    defer { try? FileManager.default.removeItem(atPath: fixtureBuildPath) }

    let workDirectory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(atPath: workDirectory) }

    let runner = SwiftPMBuildRunner(
      repoPath: fixtureRepoPath,
      configuration: .debug,
      scratchPath: (workDirectory as NSString).appendingPathComponent("scratch")
    )
    let buildResult = try runner.produceIndexStore()
    let databasePath = (workDirectory as NSString).appendingPathComponent("index-db")

    // Two independent builders over the same built store, no cache between them (D-10).
    func makeFreshBuilder() -> SCIPIndexBuilder {
      SCIPIndexBuilder(
        repoPath: fixtureRepoPath,
        indexStorePath: buildResult.indexStorePath,
        databasePath: databasePath,
        buildToolName: BuildTool.swiftpm.rawValue,
        converterVersion: "test"
      )
    }

    let index1 = try makeFreshBuilder().build()
    let data1 = try index1.serializedData()

    let index2 = try makeFreshBuilder().build()
    let data2 = try index2.serializedData()

    #expect(data1 == data2, "two fresh builds over the same store must be byte-identical")

    // Canonical-shape invariants on the emitted index (D-10, the Go bindings' port contract).
    #expect(
      index1.documents.map(\.relativePath) == index1.documents.map(\.relativePath).sorted(),
      "documents must ascend by relativePath"
    )
    #expect(
      index1.externalSymbols.map(\.symbol) == index1.externalSymbols.map(\.symbol).sorted(),
      "external symbols must ascend by symbol string"
    )
    for document in index1.documents {
      #expect(
        document.occurrences.elementsEqual(
          SCIPIndexBuilder.canonicalizedOccurrences(document.occurrences)
        ),
        "occurrences in \(document.relativePath) must be exactly the canonically ordered, deduped list (start asc, end asc, symbol asc; dedup on (symbol, range, roles))"
      )
      #expect(
        document.symbols.map(\.symbol) == document.symbols.map(\.symbol).sorted(),
        "document.symbols must ascend by symbol string"
      )
    }
  }

  // MARK: - Canonical ordering / dedup (unit)

  @Test("canonical order: start asc, end asc, symbol-string tiebreak")
  func canonicalOccurrenceOrdering() {
    // Shared start: end ascending decides even when the symbol strings would order the other
    // way (Go `Range.CompareStrict`: start asc, then end asc; `Occurrence.Compare` appends the
    // symbol tiebreak).
    let enclosed = Self.occurrence(
      symbol: "scip-swift swiftpm M . zzz().", line: 0, start: 2, end: 6)
    let enclosing = Self.occurrence(
      symbol: "scip-swift swiftpm M . aaa.", line: 0, start: 2, end: 10)
    // Different start: start position decides.
    let later = Self.occurrence(
      symbol: "scip-swift swiftpm M . bbb.", line: 0, start: 7, end: 8)
    // Equal ranges: symbol string ascending.
    let symbolB = Self.occurrence(
      symbol: "scip-swift swiftpm M . b().", line: 1, start: 0, end: 3)
    let symbolA = Self.occurrence(
      symbol: "scip-swift swiftpm M . a().", line: 1, start: 0, end: 3)

    let ordered = SCIPIndexBuilder.canonicalizedOccurrences(
      [symbolB, later, enclosing, symbolA, enclosed])

    #expect(
      ordered.map(\.symbol) == [
        enclosed.symbol, enclosing.symbol, later.symbol, symbolA.symbol, symbolB.symbol,
      ],
      "expected (start asc, end asc, symbol asc) ordering"
    )
  }

  @Test("duplicate (symbol, range, roles) occurrences collapse to one")
  func duplicateOccurrencesCollapse() {
    let original = Self.occurrence(
      symbol: "scip-swift swiftpm M . f().", line: 3, start: 4, end: 9, roles: 1)
    let exactDuplicate = Self.occurrence(
      symbol: "scip-swift swiftpm M . f().", line: 3, start: 4, end: 9, roles: 1)
    let differentRoles = Self.occurrence(
      symbol: "scip-swift swiftpm M . f().", line: 3, start: 4, end: 9, roles: 2)
    let differentRange = Self.occurrence(
      symbol: "scip-swift swiftpm M . f().", line: 3, start: 4, end: 8, roles: 1)

    let result = SCIPIndexBuilder.canonicalizedOccurrences(
      [original, exactDuplicate, differentRoles, differentRange, exactDuplicate])

    #expect(result.count == 3, "exact (symbol, range, roles) duplicates must collapse")
    #expect(
      result.elementsEqual([original, differentRange, differentRoles].sorted {
        $0.singleLineRange.endCharacter < $1.singleLineRange.endCharacter
      }),
      "survivors keep the canonical order (end asc here); roles differences are NOT duplicates"
    )
  }

  // MARK: - Metadata normalization (Pitfall 2)

  @Test("ToolInfo metadata is argv-insensitive (normalized arguments)")
  func metadataIsArgvInsensitive() throws {
    // CLI double-runs invoke the engine with different `--output` paths; embedding raw
    // `CommandLine.arguments` made those runs differ in metadata bytes. The normalization
    // choice (recorded in code + README) is to drop argv entirely. In-process argv is fixed,
    // so argv-insensitivity is asserted as "arguments stay empty": reintroducing
    // `CommandLine.arguments` repopulates them and fails this test.
    func makeBuilder() -> SCIPIndexBuilder {
      SCIPIndexBuilder(
        repoPath: "/tmp/determinism-fixture-repo",
        indexStorePath: "/tmp/nonexistent-index-store",
        databasePath: "/tmp/nonexistent-index-db",
        buildToolName: BuildTool.swiftpm.rawValue,
        converterVersion: "test"
      )
    }

    let metadata1 = makeBuilder().makeMetadata()
    let metadata2 = makeBuilder().makeMetadata()

    #expect(
      metadata1.toolInfo.arguments.isEmpty,
      "raw CommandLine.arguments must not be embedded in ToolInfo (breaks CLI double-run byte identity and leaks local paths into shared artifacts)"
    )
    #expect(metadata1.toolInfo.name == "scip-swift")
    #expect(try metadata1.serializedData() == metadata2.serializedData())
  }

  // MARK: - Fixtures and helpers

  /// The double-run fixture set: MiniSwiftPackage plus UnicodeRangeFixture, whose emoji/CJK
  /// identifiers satisfy the multi-byte proviso on the determinism double-run.
  struct FixtureCase: Sendable, CustomStringConvertible {
    let name: String
    let path: String
    var description: String { name }
  }

  private static let fixtureCases: [FixtureCase] = [
    FixtureCase(name: "MiniSwiftPackage", path: fixturePath("MiniSwiftPackage")),
    FixtureCase(name: "UnicodeRangeFixture", path: fixturePath("UnicodeRangeFixture")),
  ]

  private static func fixturePath(_ fixture: String) -> String {
    // Tests/scip-swiftTests/DeterminismTests.swift -> repo root
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return repoRoot.appendingPathComponent("Fixtures/\(fixture)").path
  }

  private static func occurrence(
    symbol: String, line: Int32, start: Int32, end: Int32, roles: Int32 = 0
  ) -> Scip_Occurrence {
    var occurrence = Scip_Occurrence()
    occurrence.symbol = symbol
    occurrence.symbolRoles = roles
    var range = Scip_SingleLineRange()
    range.line = line
    range.startCharacter = start
    range.endCharacter = end
    occurrence.singleLineRange = range
    return occurrence
  }

  private static func makeTemporaryDirectory() throws -> String {
    let path = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("scip-swift-det-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }
}
