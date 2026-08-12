import Foundation
import Testing

@testable import scip_swift

/// Requirement: TEST-05 — integration test for multi-repo merge correctness.
/// Builds two fixture packages independently, indexes each with a distinct symbolVersion,
/// merges them, and validates structural invariants matching scip lint rules.
@Suite("Multi-Repo Merge")
struct MultiRepoMergeIntegrationTests {
  @Test("merging two repo indexes produces a structurally valid combined index")
  func mergedIndexStructuralValidity() throws {
    let fixtureAPath = Self.fixturePath("CrossRepoPackageA")
    let fixtureBPath = Self.fixturePath("CrossRepoPackageB")
    let buildPathA = (fixtureAPath as NSString).appendingPathComponent(".build")
    let buildPathB = (fixtureBPath as NSString).appendingPathComponent(".build")
    defer {
      try? FileManager.default.removeItem(atPath: buildPathA)
      try? FileManager.default.removeItem(atPath: buildPathB)
    }

    let workDir = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(atPath: workDir) }

    let indexA = try Self.indexRepo(
      fixturePath: fixtureAPath,
      symbolVersion: "CrossRepoPackageA",
      workDir: (workDir as NSString).appendingPathComponent("A"),
      label: "A"
    )
    let indexB = try Self.indexRepo(
      fixturePath: fixtureBPath,
      symbolVersion: "CrossRepoPackageB",
      workDir: (workDir as NSString).appendingPathComponent("B"),
      label: "B"
    )

    let merged = ScipIndexMerger.merge(
      [indexA, indexB],
      repoIdentifiers: ["CrossRepoPackageA", "CrossRepoPackageB"],
      projectRoot: workDir
    )

    #expect(merged.documents.count >= 2, "Merged index should contain documents from both repos")

    for doc in merged.documents {
      #expect(doc.relativePath.contains("/"), "Document relativePath should be prefixed with a repo identifier: \(doc.relativePath)")
    }

    let paths = merged.documents.map(\.relativePath)
    #expect(Set(paths).count == paths.count, "No two documents should share the same relativePath")

    let definedSymbols = Set(merged.documents.flatMap { $0.symbols.map(\.symbol) })
    for external in merged.externalSymbols {
      #expect(!definedSymbols.contains(external.symbol), "External symbol should not also be defined in a document: \(external.symbol)")
    }

    let allKnownSymbols = definedSymbols.union(Set(merged.externalSymbols.map(\.symbol)))
    for doc in merged.documents {
      for occurrence in doc.occurrences where !occurrence.symbol.hasPrefix("local ") {
        #expect(allKnownSymbols.contains(occurrence.symbol), "Every occurrence symbol should have a matching SymbolInformation: \(occurrence.symbol)")
      }
    }
  }

  private static func indexRepo(fixturePath: String, symbolVersion: String, workDir: String, label: String) throws -> Scip_Index {
    try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)

    let runner = SwiftPMBuildRunner(
      repoPath: fixturePath,
      configuration: .debug,
      scratchPath: (workDir as NSString).appendingPathComponent("scratch")
    )
    let buildResult = try runner.produceIndexStore()

    let builder = SCIPIndexBuilder(
      repoPath: fixturePath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: (workDir as NSString).appendingPathComponent("index-db"),
      buildToolName: BuildTool.swiftpm.rawValue,
      converterVersion: "test",
      symbolVersion: symbolVersion
    )
    return try builder.build()
  }

  private static func fixturePath(_ name: String) -> String {
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return repoRoot.appendingPathComponent("Fixtures/\(name)").path
  }

  private static func makeTemporaryDirectory() throws -> String {
    let path = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("scip-swift-multirepo-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }
}
