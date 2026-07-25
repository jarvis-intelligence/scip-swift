import Foundation
import Testing

@testable import scip_swift

/// Requirement: run the full pipeline (build → IndexStore → SCIP) against a small real Swift
/// fixture repo (task 4.4). This actually shells out to `swift build`, so it's slower than the
/// unit tests but exercises real behavior end-to-end, per project convention (no mocks).
@Suite("Integration: build -> IndexStore -> SCIP")
struct IntegrationTests {
  @Test("full pipeline produces a valid SCIP index for the fixture package")
  func fullPipeline() throws {
    let fixtureRepoPath = Self.fixtureRepoPath()
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

    let builder = SCIPIndexBuilder(
      repoPath: fixtureRepoPath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: (workDirectory as NSString).appendingPathComponent("index-db"),
      buildToolName: BuildTool.swiftpm.rawValue,
      converterVersion: "test"
    )
    let index = try builder.build()

    #expect(index.documents.count == 1)
    let document = try #require(index.documents.first)
    #expect(document.relativePath == "Sources/MiniSwiftPackage/Greeter.swift")
    #expect(document.language == "Swift")
    #expect(!document.occurrences.isEmpty)

    let displayNames = Set(document.symbols.map(\.displayName))
    #expect(displayNames.contains("Greeter"))
    #expect(displayNames.contains("greet()"))
    #expect(displayNames.contains("name"))

    #expect(index.metadata.toolInfo.name == "scip-swift")
  }

  private static func fixtureRepoPath() -> String {
    // Tests/scip-swiftTests/IntegrationTests.swift -> repo root
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return repoRoot.appendingPathComponent("Fixtures/MiniSwiftPackage").path
  }

  private static func makeTemporaryDirectory() throws -> String {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("scip-swift-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }
}
