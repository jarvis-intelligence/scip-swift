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

  @Test("fresh run and cache-hit run over the same store are byte-identical")
  func freshVsCachedByteIdentity() throws {
    let fixtureRepoPath = Self.fixturePath("MiniSwiftPackage")
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
    let store = CacheStore(cacheDir: (workDirectory as NSString).appendingPathComponent("cache"))

    func makeBuilder() -> SCIPIndexBuilder {
      SCIPIndexBuilder(
        repoPath: fixtureRepoPath,
        indexStorePath: buildResult.indexStorePath,
        databasePath: databasePath,
        buildToolName: BuildTool.swiftpm.rawValue,
        converterVersion: "test",
        cacheStore: store
      )
    }

    // Run 1 is fresh (populates the cache); run 2 is a cache-hit pass. Both must be
    // byte-identical — external display names included, which the USR side map carries.
    let freshData = try makeBuilder().build().serializedData()
    let cachedData = try makeBuilder().build().serializedData()
    #expect(freshData == cachedData, "cache-hit run must be byte-identical to the fresh run")
  }

  @Test("cross-file overload staleness: an added earlier-sorting overload rebuilds the cached document (D-10/T-02-04)")
  func crossFileOverloadStalenessGuard() throws {
    let workDirectory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(atPath: workDirectory) }

    // A private copy of the fixture so the test can mutate it freely.
    let fixtureRepoPath = (workDirectory as NSString).appendingPathComponent("StaleFixture")
    try FileManager.default.copyItem(
      atPath: Self.fixturePath("MiniSwiftPackage"), toPath: fixtureRepoPath)

    // AAAOverloads.swift sorts BEFORE Greeter.swift, so its members take the earlier overload
    // indices; Greeter.swift's content never changes across the two states below — its cached
    // document is the staleness bait.
    let overloadsPath = (fixtureRepoPath as NSString)
      .appendingPathComponent("Sources/MiniSwiftPackage/AAAOverloads.swift")
    let scratchPath = (workDirectory as NSString).appendingPathComponent("scratch")
    let cacheDir = (workDirectory as NSString).appendingPathComponent("cache")
    let store = CacheStore(cacheDir: cacheDir)

    func rebuildIndexStore() throws -> String {
      let runner = SwiftPMBuildRunner(
        repoPath: fixtureRepoPath, configuration: .debug, scratchPath: scratchPath)
      return try runner.produceIndexStore().indexStorePath
    }
    func buildCached(indexStorePath: String, databasePath: String) throws -> Data {
      try SCIPIndexBuilder(
        repoPath: fixtureRepoPath,
        indexStorePath: indexStorePath,
        databasePath: databasePath,
        buildToolName: BuildTool.swiftpm.rawValue,
        converterVersion: "test",
        cacheStore: store
      ).build().serializedData()
    }
    func buildFresh(indexStorePath: String, databasePath: String) throws -> Data {
      try SCIPIndexBuilder(
        repoPath: fixtureRepoPath,
        indexStorePath: indexStorePath,
        databasePath: databasePath,
        buildToolName: BuildTool.swiftpm.rawValue,
        converterVersion: "test"
      ).build().serializedData()
    }

    // State 1: one extension overload in the earlier-sorting file. The group
    // (Greeter, greet) has two members, so Greeter.swift's greet renders (+1).
    try """
      extension Greeter {
        public func greet(loud: Bool) -> String { loud ? "HELLO" : greet() }
      }
      """.write(toFile: overloadsPath, atomically: true, encoding: .utf8)
    let storePath1 = try rebuildIndexStore()
    let databasePath1 = (workDirectory as NSString).appendingPathComponent("index-db-1")
    _ = try buildCached(indexStorePath: storePath1, databasePath: databasePath1)
    // The state-1 cache now holds a Greeter.swift document whose greet is (+1).

    // State 2: a new overload sorted even earlier (above the existing one) shifts every group
    // member's index: greet(quiet:) = 0, greet(loud:) = 1, Greeter.swift greet = 2.
    try """
      extension Greeter {
        public func greet(quiet: Bool) -> String { quiet ? "..." : greet(loud: false) }
        public func greet(loud: Bool) -> String { loud ? "HELLO" : greet() }
      }
      """.write(toFile: overloadsPath, atomically: true, encoding: .utf8)
    let storePath2 = try rebuildIndexStore()
    let databasePath2 = (workDirectory as NSString).appendingPathComponent("index-db-2")

    let cachedData = try buildCached(indexStorePath: storePath2, databasePath: databasePath2)
    let freshData = try buildFresh(indexStorePath: storePath2, databasePath: databasePath2)

    #expect(
      cachedData == freshData,
      "the cache-hit run must match a fresh build of the same state — a cached document must not survive an overload-table change in another file"
    )

    // Pin the exact regression: the served-for-Greeter document must carry (+2), never the
    // stale (+1) strings from the state-1 cache.
    let cachedIndex = try Scip_Index(serializedData: cachedData)
    let greeterDocument = try #require(
      cachedIndex.documents.first { $0.relativePath == "Sources/MiniSwiftPackage/Greeter.swift" }
    )
    let greetSymbols = greeterDocument.occurrences.map(\.symbol)
    #expect(
      greetSymbols.contains("scip-swift swiftpm MiniSwiftPackage . Greeter#greet(+2)."),
      "after the earlier-sorting overload is added, Greeter.greet must render (+2)"
    )
    #expect(
      !greetSymbols.contains("scip-swift swiftpm MiniSwiftPackage . Greeter#greet(+1)."),
      "the stale (+1) string from the cached state-1 document must not survive"
    )
  }

  @Test("cached run persists a per-document USR side map beside the .scipdoc (D-09)")
  func cachedRunPersistsUSRSideMap() throws {
    let fixtureRepoPath = Self.fixturePath("MiniSwiftPackage")
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

    let cacheDir = (workDirectory as NSString).appendingPathComponent("cache")
    let store = CacheStore(cacheDir: cacheDir)
    let index = try SCIPIndexBuilder(
      repoPath: fixtureRepoPath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: (workDirectory as NSString).appendingPathComponent("index-db"),
      buildToolName: BuildTool.swiftpm.rawValue,
      converterVersion: "test",
      cacheStore: store
    ).build()
    #expect(!index.documents.isEmpty)

    let greeterPath = (fixtureRepoPath as NSString)
      .appendingPathComponent("Sources/MiniSwiftPackage/Greeter.swift")
    let hash = try ContentHasher.sha256Hex(of: greeterPath)
    let cacheKey = CacheStore.documentCacheKey(
      relativePath: "Sources/MiniSwiftPackage/Greeter.swift", hash: hash)
    let docsDir = (cacheDir as NSString).appendingPathComponent("docs")
    #expect(
      FileManager.default.fileExists(
        atPath: (docsDir as NSString).appendingPathComponent("\(cacheKey).scipdoc")),
      "the Greeter document must be cached"
    )
    #expect(
      FileManager.default.fileExists(
        atPath: (docsDir as NSString).appendingPathComponent("\(cacheKey).usrmap")),
      "docs/<composite-key>.usrmap must exist beside the cached .scipdoc"
    )

    let sideMap = try #require(
      store.loadUSRMap(relativePath: "Sources/MiniSwiftPackage/Greeter.swift", hash: hash))
    #expect(!sideMap.isEmpty, "the D-06 parameter fallback must be recorded in the side map")
    for (symbolString, usr) in sideMap {
      #expect(symbolString.hasPrefix("scip-swift"), "keys are canonical symbol strings")
      #expect(symbolString.contains("`s:"), "only raw-USR fallback symbols ride the side map")
      #expect(usr.hasPrefix("s:"), "values are USRs — canonicalSymbol -> USR round-trips")
    }
  }

  @Test("ToolInfo metadata is argv-insensitive (normalized arguments)")
  func metadataIsArgvInsensitive() throws {
    // CLI double-runs invoke the engine with different `--output` paths; embedding raw
    // `CommandLine.arguments` made those runs differ in metadata bytes. The normalization
    // choice (recorded in code + README) is to drop argv entirely. In-process argv is fixed,
    // so argv-insensitivity is asserted as "arguments are exactly the constant synthetic
    // set" (D-14's scip-cli-version entry since 02-03): reintroducing
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
      metadata1.toolInfo.arguments == ["scip-cli-version=\(ScipSwiftVersion.scipCliVersion)"],
      "ToolInfo arguments must be the constant synthetic set only — raw CommandLine.arguments must not be embedded (breaks CLI double-run byte identity and leaks local paths into shared artifacts)"
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
