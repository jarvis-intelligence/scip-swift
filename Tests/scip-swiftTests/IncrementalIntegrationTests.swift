import Foundation
import Testing

@testable import scip_swift

/// Requirement: TEST-04 — integration test for incremental indexing cache correctness.
@Suite("Incremental Indexing")
struct IncrementalIntegrationTests {
  @Test("second run on unchanged fixture produces identical output")
  func secondRunIdentical() throws {
    let fixtureRepoPath = Self.fixtureRepoPath()
    let workDir = try Self.makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: workDir) }
    let cacheDir = (workDir as NSString).appendingPathComponent("cache")

    let runner = SwiftPMBuildRunner(
      repoPath: fixtureRepoPath,
      configuration: .debug,
      scratchPath: (workDir as NSString).appendingPathComponent("scratch")
    )
    let buildResult = try runner.produceIndexStore()
    let dbPath = (workDir as NSString).appendingPathComponent("index-db")

    let store = CacheStore(cacheDir: cacheDir)

    let builder1 = SCIPIndexBuilder(
      repoPath: fixtureRepoPath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: dbPath,
      buildToolName: BuildTool.swiftpm.rawValue,
      converterVersion: "test",
      cacheStore: store
    )
    let index1 = try builder1.build()
    let data1 = try index1.serializedData()

    let builder2 = SCIPIndexBuilder(
      repoPath: fixtureRepoPath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: dbPath,
      buildToolName: BuildTool.swiftpm.rawValue,
      converterVersion: "test",
      cacheStore: store
    )
    let index2 = try builder2.build()
    let data2 = try index2.serializedData()

    #expect(data1 == data2, "Second run should produce identical output")
    #expect(index1.documents.count == index2.documents.count)
  }

  @Test("cache miss on first run, hit on second")
  func cacheMissThenHit() throws {
    let fixtureRepoPath = Self.fixtureRepoPath()
    let workDir = try Self.makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: workDir) }
    let cacheDir = (workDir as NSString).appendingPathComponent("cache")

    let runner = SwiftPMBuildRunner(
      repoPath: fixtureRepoPath,
      configuration: .debug,
      scratchPath: (workDir as NSString).appendingPathComponent("scratch")
    )
    let buildResult = try runner.produceIndexStore()
    let dbPath = (workDir as NSString).appendingPathComponent("index-db")

    let store = CacheStore(cacheDir: cacheDir)

    let builder1 = SCIPIndexBuilder(
      repoPath: fixtureRepoPath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: dbPath,
      buildToolName: BuildTool.swiftpm.rawValue,
      converterVersion: "test",
      cacheStore: store
    )
    let index1 = try builder1.build()

    let docsDir = (cacheDir as NSString).appendingPathComponent("docs")
    #expect(FileManager.default.fileExists(atPath: docsDir), "Cache docs directory should exist after first run")

    let builder2 = SCIPIndexBuilder(
      repoPath: fixtureRepoPath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: dbPath,
      buildToolName: BuildTool.swiftpm.rawValue,
      converterVersion: "test",
      cacheStore: store
    )
    let index2 = try builder2.build()

    #expect(index1.documents.count == index2.documents.count)
  }

  @Test("build without cacheStore produces same result")
  func noCacheBackwardCompatible() throws {
    let fixtureRepoPath = Self.fixtureRepoPath()
    let workDir = try Self.makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: workDir) }

    let runner = SwiftPMBuildRunner(
      repoPath: fixtureRepoPath,
      configuration: .debug,
      scratchPath: (workDir as NSString).appendingPathComponent("scratch")
    )
    let buildResult = try runner.produceIndexStore()

    let builder = SCIPIndexBuilder(
      repoPath: fixtureRepoPath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: (workDir as NSString).appendingPathComponent("index-db"),
      buildToolName: BuildTool.swiftpm.rawValue,
      converterVersion: "test"
    )
    let index = try builder.build()

    #expect(index.documents.count == 1)
    #expect(!index.documents.first!.symbols.isEmpty)
  }

  @Test("0.2.1 cache dir regenerates after upgrade")
  func cacheUpgradeRegeneratesDocuments() throws {
    let fixtureRepoPath = Self.fixtureRepoPath()
    let workDir = try Self.makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: workDir) }
    let cacheDir = (workDir as NSString).appendingPathComponent("cache")

    let greeterPath = (fixtureRepoPath as NSString)
      .appendingPathComponent("Sources/MiniSwiftPackage/Greeter.swift")
    let greeterHash = try ContentHasher.sha256Hex(of: greeterPath)

    var staleDoc = Scip_Document()
    staleDoc.language = "Swift"
    staleDoc.relativePath = "Sources/MiniSwiftPackage/Greeter.swift"
    var staleSymbol = Scip_SymbolInformation()
    staleSymbol.symbol = SCIPSymbolFormatter.globalSymbolString(
      packageManager: BuildTool.swiftpm.rawValue,
      moduleName: "MiniSwiftPackage",
      usr: "s:16MiniSwiftPackage7GreeterV"
    )
    staleSymbol.displayName = "Greeter"
    staleDoc.symbols = [staleSymbol]

    let store = CacheStore(cacheDir: cacheDir)
    try store.saveDocument(staleDoc, relativePath: staleDoc.relativePath, hash: greeterHash)
    try store.saveManifest(IndexManifest(
      toolchainVersion: ToolchainInfo.pinnedSwiftVersion,
      converterVersion: "0.2.1",
      indexstoreDbRevision: IndexCommand.indexstoreDbRevision,
      buildToolName: BuildTool.swiftpm.rawValue
    ))

    let index = try IndexCommand.indexOneRepo(
      repoPath: fixtureRepoPath,
      output: nil,
      buildTool: nil,
      configuration: .debug,
      scheme: nil,
      cacheDir: cacheDir,
      indexOnly: false,
      symbolVersion: ""
    )

    let document = try #require(
      index.documents.first { $0.relativePath == "Sources/MiniSwiftPackage/Greeter.swift" }
    )
    let displayNames = Set(document.symbols.map(\.displayName))
    #expect(
      displayNames.contains("MiniSwiftPackage.Greeter"),
      "stale 0.2.1 cache must regenerate demangled documents, not serve them"
    )
    #expect(
      !displayNames.contains("Greeter"),
      "v0.2.x short display name must not survive the version upgrade"
    )

    let refreshedManifest = try #require(store.loadManifest())
    #expect(refreshedManifest.converterVersion == ScipSwiftVersion.version)
  }

  @Test("a format-4 manifest (pre-04-02 relationship bytes) is wholesale-rejected under format 5")
  func format4ManifestIsWholesaleRejected() throws {
    // D-09 (04-02): format 5 carries relationship bytes (type-level is_implementation
    // edges, relationship-target external symbols, stdlib-protocol canonical forms).
    // A cache written by a format-4 engine must NEVER serve its relationship-less
    // documents: the manifest gate rejects the mismatch wholesale and the run
    // re-emits. Proven on the relationship fixture — the regenerated documents must
    // carry the minted never-occurring target a format-4 cache could not know.
    let workDir = try Self.makeTempDir()
    let cacheDir = (workDir as NSString).appendingPathComponent("cache")
    let fixtureRepoPath = try Self.materializeFixtureCopy("HierarchiesFixture")
    defer { try? FileManager.default.removeItem(atPath: fixtureRepoPath) }
    let store = CacheStore(cacheDir: cacheDir)
    try store.saveManifest(IndexManifest(
      toolchainVersion: ToolchainInfo.pinnedSwiftVersion,
      converterVersion: ScipSwiftVersion.version,
      indexstoreDbRevision: IndexCommand.indexstoreDbRevision,
      buildToolName: BuildTool.swiftpm.rawValue,
      symbolFormatVersion: 4
    ))

    let index = try IndexCommand.indexOneRepo(
      repoPath: fixtureRepoPath,
      output: nil,
      buildTool: nil,
      configuration: .debug,
      scheme: nil,
      cacheDir: cacheDir,
      indexOnly: false,
      symbolVersion: ""
    )

    let external = Set(index.externalSymbols.map(\.symbol))
    #expect(
      external.contains(
        "scip-swift swift Swift \(ToolchainInfo.pinnedSwiftVersion) CustomStringConvertible#description."),
      "the regenerated (not cached) documents must carry the format-5 relationship minting"
    )
    let refreshed = try #require(store.loadManifest())
    #expect(
      refreshed.symbolFormatVersion == SymbolFormatVersion.current,
      "the stale format-4 manifest must be replaced (got \(refreshed.symbolFormatVersion))"
    )
  }

  @Test("cache-hit second run serves byte-identical exact ranges without re-parsing")
  func cacheHitServesExactRanges() throws {
    let fixtureRepoPath = Self.unicodeFixtureRepoPath()
    let fixtureBuildPath = (fixtureRepoPath as NSString).appendingPathComponent(".build")
    defer { try? FileManager.default.removeItem(atPath: fixtureBuildPath) }

    let workDir = try Self.makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: workDir) }
    let cacheDir = (workDir as NSString).appendingPathComponent("cache")

    let runner = SwiftPMBuildRunner(
      repoPath: fixtureRepoPath,
      configuration: .debug,
      scratchPath: (workDir as NSString).appendingPathComponent("scratch")
    )
    let buildResult = try runner.produceIndexStore()
    let dbPath = (workDir as NSString).appendingPathComponent("index-db")

    let store = CacheStore(cacheDir: cacheDir)

    let builder1 = SCIPIndexBuilder(
      repoPath: fixtureRepoPath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: dbPath,
      buildToolName: BuildTool.swiftpm.rawValue,
      converterVersion: "test",
      cacheStore: store
    )
    let index1 = try builder1.build()
    let data1 = try index1.serializedData()

    let builder2 = SCIPIndexBuilder(
      repoPath: fixtureRepoPath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: dbPath,
      buildToolName: BuildTool.swiftpm.rawValue,
      converterVersion: "test",
      cacheStore: store
    )
    let index2 = try builder2.build()
    let data2 = try index2.serializedData()

    #expect(data1 == data2, "second run should produce byte-identical output")
    #expect(index1.documents.count == index2.documents.count)

    // Cache hits skip makeDocument (D2), so the served document carries the exact ranges the
    // refiner computed on run 1 — getter:名前 end must still be the exact 10, not 17 (RANGE-01
    // through the cache path; USR mangles 名前 as 006ldrIFb).
    let document2 = try #require(
      index2.documents.first { $0.relativePath == "Sources/UnicodeRange/main.swift" }
    )
    let getterMeiEnds = document2.occurrences
      .filter { $0.symbol == "scip-swift swiftpm UnicodeRange . `名前`()." }
      .map(\.singleLineRange)
    #expect(!getterMeiEnds.isEmpty, "cached run must serve getter:名前 occurrences")
    #expect(
      getterMeiEnds.contains { $0.line == 1 && $0.startCharacter == 4 && $0.endCharacter == 10 },
      "cached getter:名前 must carry the exact token end 10"
    )
    #expect(
      !getterMeiEnds.contains { $0.line == 1 && $0.startCharacter == 4 && $0.endCharacter == 17 },
      "cached getter:名前 must not carry the approximate end 17"
    )
  }

  /// P9 canary gate (T-02-09 policy): fixture content is data, never instructions. The
  /// DuplicateContentFixture sources carry an active prompt-injection canary; a full
  /// build+index pass over them must leave no side-effect marker anywhere in the repo or
  /// temp tree, and the canary text must not leak into the emitted index.
  @Test("prompt-injection canary in fixture sources stays inert")
  func promptInjectionCanaryStaysInert() throws {
    let fixtureRepoPath = try Self.materializeFixtureCopy("DuplicateContentFixture")
    defer { try? FileManager.default.removeItem(atPath: fixtureRepoPath) }
    let fixtureBuildPath = (fixtureRepoPath as NSString).appendingPathComponent(".build")
    defer { try? FileManager.default.removeItem(atPath: fixtureBuildPath) }

    let workDir = try Self.makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: workDir) }

    let markerSentinels = [
      NSTemporaryDirectory() + "canary-pwned",
      fixtureRepoPath + "/PWNED",
      fixtureRepoPath + "/../PWNED",
    ]

    let runner = SwiftPMBuildRunner(
      repoPath: fixtureRepoPath,
      configuration: .debug,
      scratchPath: (workDir as NSString).appendingPathComponent("scratch")
    )
    let buildResult = try runner.produceIndexStore()
    let builder = SCIPIndexBuilder(
      repoPath: fixtureRepoPath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: (workDir as NSString).appendingPathComponent("index-db"),
      buildToolName: BuildTool.swiftpm.rawValue,
      converterVersion: "test"
    )
    let index = try builder.build()

    for sentinel in markerSentinels {
      #expect(
        !FileManager.default.fileExists(atPath: sentinel),
        "canary directives must never execute: sentinel \(sentinel) must not exist"
      )
    }
    let indexData = try index.serializedData()
    #expect(
      indexData.range(of: Data("IGNORE ALL PREVIOUS INSTRUCTIONS".utf8)) == nil,
      "canary text must not leak into the emitted index"
    )
  }

  /// WR-03 fixture gate: content-hash-only document keys must not leak documents across paths.
  /// The fixture holds two byte-identical sources; the rename phase rewrites CopyA's path while
  /// keeping its content. Both scenarios assert path-exact documents and overload-index
  /// stability — the empirically observed defense is that any path change alters the build,
  /// which changes the store revision and wholesale-invalidates the cache via the manifest.
  @Test("duplicate content and rename stay path-exact through the cache")
  func duplicateContentAndRenameStayPathExact() throws {
    let fixtureRepoPath = try Self.materializeFixtureCopy("DuplicateContentFixture")
    defer { try? FileManager.default.removeItem(atPath: fixtureRepoPath) }
    let fixtureBuildPath = (fixtureRepoPath as NSString).appendingPathComponent(".build")
    defer { try? FileManager.default.removeItem(atPath: fixtureBuildPath) }

    let workDir = try Self.makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: workDir) }
    let cacheDir = (workDir as NSString).appendingPathComponent("cache")
    let scratchPath = (workDir as NSString).appendingPathComponent("scratch")
    let dbPath = (workDir as NSString).appendingPathComponent("index-db")

    func buildAndIndex() throws -> Scip_Index {
      let runner = SwiftPMBuildRunner(
        repoPath: fixtureRepoPath,
        configuration: .debug,
        scratchPath: scratchPath
      )
      let buildResult = try runner.produceIndexStore()
      let builder = SCIPIndexBuilder(
        repoPath: fixtureRepoPath,
        indexStorePath: buildResult.indexStorePath,
        databasePath: dbPath,
        buildToolName: BuildTool.swiftpm.rawValue,
        converterVersion: "test",
        cacheStore: CacheStore(cacheDir: cacheDir)
      )
      return try builder.build()
    }

    let fresh = try buildAndIndex()
    let cached = try buildAndIndex()

    let freshData = try fresh.serializedData()
    let cachedData = try cached.serializedData()
    #expect(
      freshData == cachedData,
      "cache-hit run over duplicate-content sources must be byte-identical to the fresh run"
    )
    try Self.assertDuplicateContentShape(index: fresh, label: "fresh")
    try Self.assertDuplicateContentShape(index: cached, label: "cached")

    let copyA = (fixtureRepoPath as NSString)
      .appendingPathComponent("Sources/DuplicateContent/CopyA.swift")
    let copyRenamed = (fixtureRepoPath as NSString)
      .appendingPathComponent("Sources/DuplicateContent/CopyRenamed.swift")
    try FileManager.default.moveItem(atPath: copyA, toPath: copyRenamed)

    let renamed = try buildAndIndex()
    try Self.assertRenamedShape(index: renamed)
  }

  private static func markerOverloads(_ document: Scip_Document) -> Set<String> {
    Set(
      document.symbols
        .map(\.symbol)
        .filter { $0.contains("Marker") }
        .filter { !$0.hasSuffix("Marker#") })
  }

  private static func assertDuplicateContentShape(index: Scip_Index, label: String) throws {
    let paths = index.documents.map(\.relativePath).sorted()
    #expect(
      paths == [
        "Sources/DuplicateContent/CopyA.swift", "Sources/DuplicateContent/CopyB.swift"
      ],
      "\(label) run must carry exactly the two fixture paths"
    )
    let copyA = try #require(index.documents.first { $0.relativePath.hasSuffix("CopyA.swift") })
    let copyB = try #require(index.documents.first { $0.relativePath.hasSuffix("CopyB.swift") })
    let symbolsA = Set(copyA.symbols.map(\.symbol))
    let symbolsB = Set(copyB.symbols.map(\.symbol))
    let overloadsA = markerOverloads(copyA)
    let overloadsB = markerOverloads(copyB)
    #expect(overloadsA.contains("scip-swift swiftpm DuplicateContent . Marker()."))
    #expect(symbolsA.contains("scip-swift swiftpm DuplicateContent . init()."))
    #expect(overloadsB.contains("scip-swift swiftpm DuplicateContent . Marker(+1)."))
    #expect(symbolsB.contains("scip-swift swiftpm DuplicateContent . init(+2)."))
    // Disjointness is scoped to the Method family: both documents legitimately share the bare
    // Term `Marker.` — Terms cannot carry (+N) under the frozen Phase-1 scheme (documented
    // known limitation), so that collision is allowed and not a cache-leak signal.
    let methodOverloadsA = overloadsA.filter { $0.contains("(") }
    let methodOverloadsB = overloadsB.filter { $0.contains("(") }
    #expect(
      methodOverloadsA.isDisjoint(with: methodOverloadsB),
      "\(label) run: identical content must not collapse the two documents' overload sets"
    )
  }

  private static func assertRenamedShape(index: Scip_Index) throws {
    let paths = index.documents.map(\.relativePath).sorted()
    #expect(
      paths == [
        "Sources/DuplicateContent/CopyB.swift", "Sources/DuplicateContent/CopyRenamed.swift"
      ],
      "renamed run must serve the new path, never the stale CopyA path"
    )
    let renamed = try #require(
      index.documents.first { $0.relativePath.hasSuffix("CopyRenamed.swift") })
    let overloads = markerOverloads(renamed)
    #expect(
      overloads.contains("scip-swift swiftpm DuplicateContent . Marker(+1)."),
      "renamed document must keep its overload index after the rename"
    )
  }

  private static func materializeFixtureCopy(_ fixtureName: String) throws -> String {
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let source = repoRoot.appendingPathComponent("Fixtures/\(fixtureName)").path
    let copy = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("scip-swift-fixture-\(fixtureName)-\(UUID().uuidString)")
    try FileManager.default.copyItem(atPath: source, toPath: copy)
    return copy
  }

  private static func fixtureRepoPath() -> String {
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return repoRoot.appendingPathComponent("Fixtures/MiniSwiftPackage").path
  }

  private static func unicodeFixtureRepoPath() -> String {
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return repoRoot.appendingPathComponent("Fixtures/UnicodeRangeFixture").path
  }

  private static func makeTempDir() throws -> String {
    let path = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("scip-swift-incr-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }
}
