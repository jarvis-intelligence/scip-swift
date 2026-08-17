import Foundation
import Testing

@testable import scip_swift

@Suite("CacheStore")
struct CacheStoreTests {
  @Test("saveDocument then loadDocument returns identical protobuf")
  func saveLoadRoundTrip() throws {
    let cache = CacheStore(cacheDir: makeTempDir())

    var doc = Scip_Document()
    doc.language = "Swift"
    doc.relativePath = "test.swift"
    var occ = Scip_Occurrence()
    occ.symbol = "scip-swift test . foo."
    doc.occurrences.append(occ)

    try cache.saveDocument(doc, hash: "abcdef123456")
    let loaded = cache.loadDocument(hash: "abcdef123456")

    #expect(loaded != nil)
    #expect(loaded?.language == "Swift")
    #expect(loaded?.relativePath == "test.swift")
    #expect(loaded?.occurrences.count == 1)
  }

  @Test("documentation field survives the protobuf round-trip intact")
  func documentationRoundTrip() throws {
    let cache = CacheStore(cacheDir: makeTempDir())

    var doc = Scip_Document()
    doc.language = "Swift"
    doc.relativePath = "docs.swift"
    var symbol = Scip_SymbolInformation()
    symbol.symbol = "scip-swift test . docsym."
    symbol.documentation = ["First doc line.", "", "Second doc line."]
    doc.symbols = [symbol]

    try cache.saveDocument(doc, hash: "docroundtrip")
    let loaded = cache.loadDocument(hash: "docroundtrip")

    let loadedSymbol = try #require(loaded?.symbols.first)
    #expect(loadedSymbol.documentation == ["First doc line.", "", "Second doc line."])
  }

  @Test("loadDocument returns nil for non-existent hash")
  func loadNonExistentReturnsNil() {
    let cache = CacheStore(cacheDir: makeTempDir())
    #expect(cache.loadDocument(hash: "nonexistent") == nil)
  }

  @Test("saveManifest then loadManifest round-trips")
  func manifestRoundTrip() throws {
    let cache = CacheStore(cacheDir: makeTempDir())
    let manifest = IndexManifest(
      toolchainVersion: "6.2.4",
      converterVersion: "0.1.2",
      indexstoreDbRevision: "c993f4fb",
      buildToolName: "swiftpm"
    )
    try cache.saveManifest(manifest)
    let loaded = try cache.loadManifest()
    #expect(loaded != nil)
    #expect(loaded?.toolchainVersion == "6.2.4")
    #expect(loaded?.buildToolName == "swiftpm")
  }

  @Test("loadManifest returns nil when no manifest exists")
  func loadManifestEmpty() throws {
    let cache = CacheStore(cacheDir: makeTempDir())
    let loaded = try cache.loadManifest()
    #expect(loaded == nil)
  }

  @Test("invalidateAll removes cached docs and manifest, keeps the cache directory")
  func invalidateAllRemovesCacheContents() throws {
    let dir = makeTempDir()
    let cache = CacheStore(cacheDir: dir)

    var doc = Scip_Document()
    doc.language = "Swift"
    try cache.saveDocument(doc, hash: "testhash")
    try cache.saveManifest(IndexManifest(
      toolchainVersion: "6.2.4",
      converterVersion: "0.1.2",
      indexstoreDbRevision: "c993f4fb",
      buildToolName: "swiftpm"
    ))

    let docsDir = (dir as NSString).appendingPathComponent("docs")
    let manifestPath = (dir as NSString).appendingPathComponent("manifest.json")

    try cache.invalidateAll()
    #expect(!FileManager.default.fileExists(atPath: docsDir), "docs/ must be removed")
    #expect(!FileManager.default.fileExists(atPath: manifestPath), "manifest.json must be removed")
    #expect(
      FileManager.default.fileExists(atPath: dir),
      "cache dir itself must survive — callers park build scratch beside the document cache"
    )
    #expect(cache.loadDocument(hash: "testhash") == nil)
    #expect(try cache.loadManifest() == nil)
  }

  @Test("saveDocument creates nested docs directory")
  func saveCreatesDocsDir() throws {
    let dir = makeTempDir()
    let cache = CacheStore(cacheDir: dir)

    var doc = Scip_Document()
    doc.language = "Swift"
    try cache.saveDocument(doc, hash: "testhash")

    let docsDir = (dir as NSString).appendingPathComponent("docs")
    #expect(FileManager.default.fileExists(atPath: docsDir))
  }

  @Test("loadDocument after cache recreated works")
  func cacheRecreatedWorks() throws {
    let dir = makeTempDir()
    let cache = CacheStore(cacheDir: dir)

    var doc = Scip_Document()
    doc.language = "Swift"
    doc.relativePath = "test.swift"

    try cache.saveDocument(doc, hash: "recreate")
    try cache.invalidateAll()
    try cache.saveDocument(doc, hash: "recreate")
    let loaded = cache.loadDocument(hash: "recreate")

    #expect(loaded != nil)
    #expect(loaded?.language == "Swift")
  }

  private func makeTempDir() -> String {
    let dir = NSTemporaryDirectory() + "cache-test-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
  }
}
