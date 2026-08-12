import Foundation
import Testing

@testable import scip_swift

@Suite("ScipIndexMerger")
struct ScipIndexMergerTests {
  @Test("merging two indexes concatenates documents from both")
  func documentsConcatenated() {
    var docA = Scip_Document()
    docA.relativePath = "Sources/RepoA/Foo.swift"

    var docB = Scip_Document()
    docB.relativePath = "Sources/RepoA/Bar.swift"

    var indexA = Scip_Index()
    indexA.documents = [docA]

    var indexB = Scip_Index()
    indexB.documents = [docB]

    let merged = ScipIndexMerger.merge([indexA, indexB], projectRoot: "/test")

    #expect(merged.documents.count == 2)
    let paths = merged.documents.map(\.relativePath)
    #expect(paths.contains("Sources/RepoA/Foo.swift"))
    #expect(paths.contains("Sources/RepoA/Bar.swift"))
  }

  @Test("merging deduplicates external symbols that appear in both indexes")
  func externalSymbolsDeduplicated() {
    let sharedSymbol = "scip-swift swiftpm Shared . `s:Shared`."

    var external = Scip_SymbolInformation()
    external.symbol = sharedSymbol

    var indexA = Scip_Index()
    indexA.externalSymbols = [external]

    var indexB = Scip_Index()
    indexB.externalSymbols = [external]

    let merged = ScipIndexMerger.merge([indexA, indexB], projectRoot: "/test")

    let matching = merged.externalSymbols.filter { $0.symbol == sharedSymbol }
    #expect(matching.count == 1)
  }

  @Test("merged metadata uses the supplied projectRoot, not the first index's projectRoot")
  func metadataProjectRootOverridden() {
    var indexA = Scip_Index()
    indexA.metadata.projectRoot = "file:///original/"

    var indexB = Scip_Index()
    indexB.metadata.projectRoot = "file:///other/"

    let merged = ScipIndexMerger.merge([indexA, indexB], projectRoot: "/custom/root")

    #expect(merged.metadata.projectRoot == "file:///custom/root/")
  }

  @Test("merging zero indexes returns an empty Scip_Index without crashing")
  func emptyInput() {
    let merged = ScipIndexMerger.merge([], projectRoot: "/test")

    #expect(merged.documents.isEmpty)
    #expect(merged.externalSymbols.isEmpty)
  }
}
