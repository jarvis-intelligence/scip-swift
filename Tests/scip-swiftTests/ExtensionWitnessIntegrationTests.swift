import Foundation
import IndexStoreDB
import Testing

@testable import scip_swift

/// Uses the converter API available before the fix so the baseline fails assertions.
@Suite("Integration: extension witnesses")
struct ExtensionWitnessIntegrationTests {
  private let prefix = "scip-swift swiftpm ExtensionWitnessFixture . "
  private let sourceDirectory = "Sources/ExtensionWitnessFixture/"

  @Test("witness relations follow the definition across files and cached documents")
  func extensionWitnesses() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let fixture = root.appendingPathComponent("Fixtures/ExtensionWitnessFixture")
    let work = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("extension-witness-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: work) }
    let result = try SwiftPMBuildRunner(
      repoPath: fixture.path, configuration: .debug,
      scratchPath: work.appendingPathComponent("build").path
    ).produceIndexStore()
    let database = work.appendingPathComponent("db").path

    // Verify the compiler fixture actually exercises the non-definition relation path.
    do {
      let store = try IndexStoreLoader.open(storePath: result.indexStorePath, databasePath: database)
      store.pollForUnitChangesAndWait()
      let definitions = store.symbolOccurrences(
        inFilePath: fixture.appendingPathComponent(sourceDirectory + "Shapes.swift").path)
      let circle = try #require(definitions.first {
        $0.symbol.name == "area()" && $0.location.line == 11 && $0.roles.contains(.definition)
      })
      #expect(!circle.relations.contains { $0.roles.contains(.overrideOf) })
      for (line, file, anchor) in [(11, "Shapes.swift", 13), (15, "ZConformance.swift", 1),
                                    (18, "AConformance.swift", 1)] {
        let definition = try #require(definitions.first {
          $0.symbol.name == "area()" && $0.location.line == line && $0.roles.contains(.definition)
        })
        let occurrences = store.symbolOccurrences(
          inFilePath: fixture.appendingPathComponent(sourceDirectory + file).path)
        #expect(occurrences.contains {
          $0.symbol.usr == definition.symbol.usr && $0.location.line == anchor
            && !$0.roles.contains(.definition)
            && $0.relations.contains { $0.roles.contains(.overrideOf) }
        })
      }
    }

    let cache = CacheStore(cacheDir: work.appendingPathComponent("cache").path)
    func build(cache: CacheStore?) throws -> Scip_Index {
      try SCIPIndexBuilder(
        repoPath: fixture.path, indexStorePath: result.indexStorePath, databasePath: database,
        buildToolName: "swiftpm", converterVersion: "test", cacheStore: cache, demangle: false
      ).build()
    }
    let fresh = try build(cache: cache)
    try check(fresh)
    #expect(try build(cache: cache).serializedData() == fresh.serializedData())

    // Seed an old/stale cached edge without changing the file or the store. Cache hits
    // must replace it with the current union, including clearing a removed relationship.
    let hash = try ContentHasher.sha256Hex(
      of: fixture.appendingPathComponent(sourceDirectory + "Shapes.swift").path)
    let path = sourceDirectory + "Shapes.swift"
    var cached = try #require(cache.loadDocument(relativePath: path, hash: hash))
    var stale = Scip_Relationship()
    stale.symbol = prefix + "OtherShape#area()."
    stale.isImplementation = true
    stale.isReference = true
    for i in cached.symbols.indices where cached.symbols[i].symbol.hasSuffix("#area().") {
      cached.symbols[i].relationships = [stale]
    }
    try cache.saveDocument(cached, relativePath: path, hash: hash)
    let refreshed = try build(cache: cache)
    try check(refreshed)
    #expect(try refreshed.serializedData() == fresh.serializedData())
    #expect(try build(cache: nil).serializedData() == fresh.serializedData())
  }

  private func check(_ index: Scip_Index) throws {
    let shapes = try #require(index.documents.first {
      $0.relativePath == sourceDirectory + "Shapes.swift"
    })
    for (type, line, targets) in [
      ("Square", Int32(7), ["Shape"]), ("Circle", 10, ["OtherShape", "Shape"]),
      ("Remote", 14, ["Shape"]), ("Early", 17, ["Shape"]), ("Unrelated", 20, []),
    ] {
      let symbol = prefix + type + "#area()."
      let info = try #require(shapes.symbols.first { $0.symbol == symbol })
      #expect(info.relationships.map(\.symbol) == targets.map { prefix + $0 + "#area()." })
      #expect(info.relationships.allSatisfy {
        $0.isReference && $0.isImplementation && !$0.isDefinition && !$0.isTypeDefinition
      })
      let definitions = index.documents.flatMap(\.occurrences).filter {
        $0.symbol == symbol && $0.symbolRoles & 1 != 0
      }
      #expect(definitions.count == 1, "the extension must never become a witness definition")
      let definition = try #require(definitions.first)
      #expect(definition.singleLineRange.line == line)
      #expect(definition.singleLineRange.startCharacter == 14)
      #expect(definition.singleLineRange.endCharacter == 18)
      for document in index.documents where document.relativePath != shapes.relativePath {
        #expect(!document.symbols.contains { $0.symbol == symbol })
      }
      for occurrence in index.documents.flatMap(\.occurrences)
      where occurrence.symbol == symbol && occurrence.symbolRoles & 1 == 0 {
        #expect(occurrence.enclosingRange.isEmpty)
      }
    }
    // Preserve upstream's type-level edges, including carriers in extension files.
    for (type, targets) in [("Square", ["Shape"]), ("Circle", ["OtherShape", "Shape"]),
                            ("Remote", ["Shape"]), ("Early", ["Shape"])] {
      let edges = index.documents.flatMap(\.symbols)
        .filter { $0.symbol == prefix + type + "#" }.flatMap(\.relationships)
      #expect(Set(edges.map(\.symbol)) == Set(targets.map { prefix + $0 + "#" }))
      #expect(edges.allSatisfy { $0.isImplementation && !$0.isReference })
    }
  }
}
