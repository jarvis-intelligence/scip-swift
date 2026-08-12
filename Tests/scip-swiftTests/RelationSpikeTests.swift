import Foundation
import IndexStoreDB
import Testing

@testable import scip_swift

/// Requirement: META-06 — empirically validate that the Swift compiler populates
/// `occurrence.relations` for Swift code patterns.
///
/// Each test builds the fixture, opens IndexStoreDB, and queries occurrences inline
/// (not via a helper with defer cleanup — the IndexStoreDB handle must outlive the
/// temp directory it reads from).
@Suite("META-06: Relation Spike")
struct RelationSpikeTests {

  @Test("class inheritance: Dog.makeSound has overrideOf relation to Animal.makeSound")
  func classInheritanceRelation() throws {
    let fixtureRepoPath = Self.fixtureRepoPath()
    let workDirectory = try Self.makeTemporaryDirectory()

    let runner = SwiftPMBuildRunner(
      repoPath: fixtureRepoPath,
      configuration: .debug,
      scratchPath: (workDirectory as NSString).appendingPathComponent("scratch")
    )
    let buildResult = try runner.produceIndexStore()

    let indexStoreDB = try IndexStoreLoader.open(
      storePath: buildResult.indexStorePath,
      databasePath: (workDirectory as NSString).appendingPathComponent("index-db")
    )

    let spikeFilePath = (fixtureRepoPath as NSString)
      .appendingPathComponent("Sources/RelationSpike/Spike.swift")

    let occurrences = indexStoreDB.symbolOccurrences(inFilePath: spikeFilePath)

    let dogMakeSound = try #require(
      occurrences.first {
        $0.symbol.name == "makeSound()" && $0.roles.contains(.definition) && $0.roles.contains(.overrideOf)
      }
    )

    printDiagnostic("Dog.makeSound (override)", dogMakeSound)
    #expect(!dogMakeSound.relations.isEmpty, "override method should have relations")
    #expect(dogMakeSound.roles.contains(.overrideOf), "should have .overrideOf role")
    #expect(dogMakeSound.roles.contains(.childOf), "should have .childOf role pointing to Dog")
  }

  @Test("protocol conformance: Greeter.greet has childOf relation")
  func protocolConformanceRelation() throws {
    let fixtureRepoPath = Self.fixtureRepoPath()
    let workDirectory = try Self.makeTemporaryDirectory()

    let runner = SwiftPMBuildRunner(
      repoPath: fixtureRepoPath,
      configuration: .debug,
      scratchPath: (workDirectory as NSString).appendingPathComponent("scratch")
    )
    let buildResult = try runner.produceIndexStore()

    let indexStoreDB = try IndexStoreLoader.open(
      storePath: buildResult.indexStorePath,
      databasePath: (workDirectory as NSString).appendingPathComponent("index-db")
    )

    let spikeFilePath = (fixtureRepoPath as NSString)
      .appendingPathComponent("Sources/RelationSpike/Spike.swift")

    let occurrences = indexStoreDB.symbolOccurrences(inFilePath: spikeFilePath)

    let greeterGreet = try #require(
      occurrences.first {
        $0.symbol.name == "greet()" && $0.roles.contains(.definition) && $0.roles.contains(.childOf)
      }
    )

    printDiagnostic("Greeter.greet (conformance)", greeterGreet)
    #expect(greeterGreet.roles.contains(.childOf), "should have .childOf role")
  }

  @Test("dump all occurrence relations via SCIPIndexBuilder")
  func dumpAllRelations() throws {
    let fixtureRepoPath = Self.fixtureRepoPath()
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

    print("=== META-06 FULL RELATION DUMP (via SCIPIndexBuilder) ===")
    print("Documents: \(index.documents.count)")
    for doc in index.documents {
      print("Document: \(doc.relativePath), symbols: \(doc.symbols.count)")
      for sym in doc.symbols {
        print("  SYMBOL: \(sym.displayName) kind=\(sym.kind) rels=\(sym.relationships.count)")
      }
    }
    print("=== END DUMP ===")

    #expect(index.documents.count > 0, "should have at least one document from the spike fixture")
    let document = try #require(index.documents.first)
    let displayNames = Set(document.symbols.map(\.displayName))
    #expect(displayNames.contains("Dog"), "Dog class should be in the index")
  }

  private func printDiagnostic(_ label: String, _ occ: SymbolOccurrence) {
    print("SPIKE [\(label)]: \(occ.symbol.name) [\(occ.symbol.usr)] roles=\(occ.roles)")
    if occ.relations.isEmpty {
      print("  ↳ NO RELATIONS")
    }
    for rel in occ.relations {
      print("  ↳ RELATION: \(rel.symbol.name) [\(rel.symbol.usr)] roles=\(rel.roles)")
    }
  }

  private static func fixtureRepoPath() -> String {
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return repoRoot.appendingPathComponent("Fixtures/RelationSpikeFixture").path
  }

  private static func makeTemporaryDirectory() throws -> String {
    let path = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("scip-swift-spike-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }
}
