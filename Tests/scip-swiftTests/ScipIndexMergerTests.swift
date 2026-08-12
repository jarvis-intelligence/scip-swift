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

  @Test("external symbol also defined in a merged document is excluded from externalSymbols")
  func stripsExternalsDefinedInDocuments() {
    let symbol = "scip-swift swiftpm CrossRepoPackageA . `s:Shared`."

    var defined = Scip_SymbolInformation()
    defined.symbol = symbol

    var doc = Scip_Document()
    doc.relativePath = "Sources/RepoA/Shared.swift"
    doc.symbols = [defined]

    var external = Scip_SymbolInformation()
    external.symbol = symbol

    var indexA = Scip_Index()
    indexA.documents = [doc]

    var indexB = Scip_Index()
    indexB.externalSymbols = [external]

    let merged = ScipIndexMerger.merge([indexA, indexB], projectRoot: "/test")

    let matching = merged.externalSymbols.filter { $0.symbol == symbol }
    #expect(matching.isEmpty)
  }

  @Test("external symbol not defined in any document is preserved in externalSymbols")
  func preservesUndefinedExternalSymbols() {
    let relationshipTarget = "scip-swift swiftpm SomeExternalModule . `s:External`."

    var external = Scip_SymbolInformation()
    external.symbol = relationshipTarget

    var indexA = Scip_Index()
    indexA.externalSymbols = [external]

    let indexB = Scip_Index()

    let merged = ScipIndexMerger.merge([indexA, indexB], projectRoot: "/test")

    let matching = merged.externalSymbols.filter { $0.symbol == relationshipTarget }
    #expect(matching.count == 1)
  }

  @Test("two documents with the same relativePath get distinct paths when repoIdentifiers are passed")
  func distinctPathsForSameRelativePath() {
    var docA = Scip_Document()
    docA.relativePath = "Sources/Core/Shared.swift"

    var docB = Scip_Document()
    docB.relativePath = "Sources/Core/Shared.swift"

    var indexA = Scip_Index()
    indexA.documents = [docA]

    var indexB = Scip_Index()
    indexB.documents = [docB]

    let merged = ScipIndexMerger.merge(
      [indexA, indexB],
      repoIdentifiers: ["CrossRepoPackageA", "CrossRepoPackageB"],
      projectRoot: "/test"
    )

    let paths = merged.documents.map(\.relativePath)
    #expect(paths.contains("CrossRepoPackageA/Sources/Core/Shared.swift"))
    #expect(paths.contains("CrossRepoPackageB/Sources/Core/Shared.swift"))
    #expect(Set(paths).count == 2)
  }

  @Test("merged document relativePath is prefixed with the repo identifier")
  func relativePathPrefixedWithRepoIdentifier() throws {
    var doc = Scip_Document()
    doc.relativePath = "Sources/CrossRepoPackageA/Shared.swift"

    var index = Scip_Index()
    index.documents = [doc]

    let merged = ScipIndexMerger.merge(
      [index],
      repoIdentifiers: ["CrossRepoPackageA"],
      projectRoot: "/test"
    )

    let path = try #require(merged.documents.first?.relativePath)
    #expect(path == "CrossRepoPackageA/Sources/CrossRepoPackageA/Shared.swift")
  }

  @Test("external symbol appearing in three input indexes appears exactly once in merged output")
  func deduplicatesAcrossThreeIndexes() {
    let symbol = "scip-swift swiftpm SharedModule . `s:Shared`."

    var external = Scip_SymbolInformation()
    external.symbol = symbol

    var indexA = Scip_Index()
    indexA.externalSymbols = [external]

    var indexB = Scip_Index()
    indexB.externalSymbols = [external]

    var indexC = Scip_Index()
    indexC.externalSymbols = [external]

    let merged = ScipIndexMerger.merge([indexA, indexB, indexC], projectRoot: "/test")

    let matching = merged.externalSymbols.filter { $0.symbol == symbol }
    #expect(matching.count == 1)
  }

  @Test("external symbols in merged output are sorted by symbol string")
  func externalSymbolsSortedBySymbol() {
    var ext1 = Scip_SymbolInformation()
    ext1.symbol = "scip-swift swiftpm Zeta . `s:Z`."

    var ext2 = Scip_SymbolInformation()
    ext2.symbol = "scip-swift swiftpm Alpha . `s:A`."

    var ext3 = Scip_SymbolInformation()
    ext3.symbol = "scip-swift swiftpm Mu . `s:M`."

    var indexA = Scip_Index()
    indexA.externalSymbols = [ext1, ext2]

    var indexB = Scip_Index()
    indexB.externalSymbols = [ext3]

    let merged = ScipIndexMerger.merge([indexA, indexB], projectRoot: "/test")

    let symbols = merged.externalSymbols.map(\.symbol)
    #expect(symbols == symbols.sorted())
  }
}
