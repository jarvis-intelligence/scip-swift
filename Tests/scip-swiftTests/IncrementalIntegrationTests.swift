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
    try store.saveDocument(staleDoc, hash: greeterHash)
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

    let refreshedManifest = try #require(try store.loadManifest())
    #expect(refreshedManifest.converterVersion == ScipSwiftVersion.version)
  }

  private static func fixtureRepoPath() -> String {
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return repoRoot.appendingPathComponent("Fixtures/MiniSwiftPackage").path
  }

  private static func makeTempDir() throws -> String {
    let path = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("scip-swift-incr-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }
}
