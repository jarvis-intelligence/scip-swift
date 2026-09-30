import Foundation
import Testing

@testable import scip_swift

/// These probes use the builder API present on upstream main, so the baseline fails assertions,
/// rather than failing to compile because a new test seam is missing.
@Suite("Integration: source ranges and identity")
struct SourceIdentityIntegrationTests {
  private func build() throws -> Scip_Index {
    try buildWithDiagnostics().index
  }

  private func buildWithDiagnostics() throws -> (
    index: Scip_Index, diagnostics: SymbolMappingDiagnostics
  ) {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let fixture = root.appendingPathComponent("Fixtures/SourceIdentityFixture").path
    let work = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("source-identity-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: work) }
    let result = try SwiftPMBuildRunner(
      repoPath: fixture, configuration: .debug,
      scratchPath: work.appendingPathComponent("build").path
    ).produceIndexStore()
    let builder = SCIPIndexBuilder(
      repoPath: fixture, indexStorePath: result.indexStorePath,
      databasePath: work.appendingPathComponent("db").path,
      buildToolName: "swiftpm", converterVersion: "test", demangle: false
    )
    return (try builder.build(), builder.symbolMappingDiagnostics)
  }

  @Test("definition occurrences enclose the complete method body")
  func declarationRanges() throws {
    let index = try build()
    let method = try #require(index.documents.flatMap(\.occurrences).first {
      $0.symbol == "scip-swift swiftpm SourceIdentityFixture . Probe#read()."
        && $0.symbolRoles & 1 != 0
    })
    #expect(method.enclosingRange == [9, 2, 11, 3])
  }

  @Test("private properties and file-private variables remain distinct at definitions and uses")
  func privateIdentities() throws {
    let index = try build()
    var loggers: Set<String> = []
    var properties: Set<String> = []
    let names: Set<String> = ["first", "second", "third", "fourth", "fifth", "sixth"]
    for document in index.documents {
      for info in document.symbols where info.displayName == "logger" || names.contains(info.displayName) {
        if info.displayName == "logger" { loggers.insert(info.symbol) }
        else { properties.insert(info.symbol) }
        #expect(document.occurrences.contains { $0.symbol == info.symbol && $0.symbolRoles & 1 == 0 })
      }
    }
    #expect(loggers.count == 3)
    #expect(properties.count == 6)
  }

  @Test("projected getter anchors cover the source token and stay within its line")
  func projectedRanges() throws {
    let index = try build()
    let document = try #require(index.documents.first { $0.relativePath.hasSuffix("/Probe.swift") })
    let projected = document.occurrences.filter { $0.singleLineRange.line == 10 }
    #expect(!projected.isEmpty)
    for occurrence in projected {
      #expect(occurrence.singleLineRange.startCharacter == 4)
      #expect(occurrence.singleLineRange.endCharacter == 14)
    }
  }

  @Test("each file's colliding private type and all its members resolve under one defined parent")
  func privateTypesKeepMembersUnderTheirParent() throws {
    let index = try build()
    var parents: Set<String> = []
    for file in ["/Second.swift", "/Third.swift"] {
      let document = try #require(index.documents.first { $0.relativePath.hasSuffix(file) })
      let markers = document.symbols.map(\.symbol).filter { $0.contains("Marker") }
      let types = markers.filter { $0.hasSuffix("#") }
      #expect(types.count == 1, "\(file): \(markers)")
      let parent = try #require(types.first)
      parents.insert(parent)
      #expect(parent.hasPrefix("scip-swift swiftpm SourceIdentityFixture . `Marker@"))
      #expect(document.occurrences.contains { $0.symbol == parent && $0.symbolRoles & 1 != 0 })
      #expect(markers.allSatisfy { $0.hasPrefix(parent) }, "\(file): \(markers)")
      for member in ["value.", "value().", "touch()."] {
        #expect(markers.contains(parent + member), "\(file): missing \(member) in \(markers)")
      }
      // The use in this file's function resolves to this file's definition.
      #expect(document.occurrences.contains {
        $0.symbol == parent + "touch()." && $0.symbolRoles & 1 == 0
      })
      #expect(!document.occurrences.contains {
        $0.symbol.contains(" . Marker#") || $0.symbol.contains(" . Marker.")
      })
    }
    #expect(parents.count == 2)
  }

  @Test("a private property keeps its name next to an initializer labelled like it")
  func constructorLabelIsNotAName() throws {
    let index = try build()
    let document = try #require(index.documents.first { $0.relativePath.hasSuffix("/Fourth.swift") })
    let symbols = Set(document.symbols.map(\.symbol))
    let property = "scip-swift swiftpm SourceIdentityFixture . Service#dependencies."
    #expect(symbols.contains(property), "\(symbols.sorted())")
    #expect(document.occurrences.contains { $0.symbol == property && $0.symbolRoles & 1 == 0 })
    #expect(!symbols.contains { $0.contains("@") }, "\(symbols.sorted())")
  }

  @Test("the fallback diagnostic counts each emitted raw-USR fallback once")
  func fallbackCountIsNotInflated() throws {
    let (index, diagnostics) = try buildWithDiagnostics()
    // Every raw-USR fallback renders its USR as the escaped last descriptor.
    var emitted: [String] = index.externalSymbols.map(\.symbol)
    for document in index.documents {
      emitted += document.occurrences.map(\.symbol)
      for info in document.symbols {
        emitted += [info.symbol, info.enclosingSymbol] + info.relationships.map(\.symbol)
      }
    }
    let usrs = Set(emitted.compactMap { symbol -> String? in
      guard symbol.hasSuffix("`."), let open = symbol.range(of: " `", options: .backwards)
      else { return nil }
      let usr = String(symbol[open.upperBound..<symbol.index(symbol.endIndex, offsetBy: -2)])
      return usr.hasPrefix("s:") || usr.hasPrefix("c:") ? usr : nil
    })
    #expect(!usrs.isEmpty, "the fixture must exercise the fallback")
    #expect(diagnostics.fallbackCount == usrs.count, "\(diagnostics.summary ?? "silent")")
  }
}
