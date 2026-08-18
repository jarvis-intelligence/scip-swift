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

    try cache.saveDocument(doc, relativePath: "test.swift", hash: "abcdef123456")
    let loaded = cache.loadDocument(relativePath: "test.swift", hash: "abcdef123456")

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

    try cache.saveDocument(doc, relativePath: "docs.swift", hash: "docroundtrip")
    let loaded = cache.loadDocument(relativePath: "docs.swift", hash: "docroundtrip")

    let loadedSymbol = try #require(loaded?.symbols.first)
    #expect(loadedSymbol.documentation == ["First doc line.", "", "Second doc line."])
  }

  @Test("loadDocument returns nil for non-existent hash")
  func loadNonExistentReturnsNil() {
    let cache = CacheStore(cacheDir: makeTempDir())
    #expect(cache.loadDocument(relativePath: "test.swift", hash: "nonexistent") == nil)
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
    let loaded = cache.loadManifest()
    #expect(loaded != nil)
    #expect(loaded?.toolchainVersion == "6.2.4")
    #expect(loaded?.buildToolName == "swiftpm")
  }

  @Test("loadManifest returns nil when no manifest exists")
  func loadManifestEmpty() throws {
    let cache = CacheStore(cacheDir: makeTempDir())
    let loaded = cache.loadManifest()
    #expect(loaded == nil)
  }

  @Test("invalidateAll removes cached docs and manifest, keeps the cache directory")
  func invalidateAllRemovesCacheContents() throws {
    let dir = makeTempDir()
    let cache = CacheStore(cacheDir: dir)

    var doc = Scip_Document()
    doc.language = "Swift"
    try cache.saveDocument(doc, relativePath: "test.swift", hash: "testhash")
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
    #expect(cache.loadDocument(relativePath: "test.swift", hash: "testhash") == nil)
    #expect(cache.loadManifest() == nil)
  }

  @Test("saveDocument creates nested docs directory")
  func saveCreatesDocsDir() throws {
    let dir = makeTempDir()
    let cache = CacheStore(cacheDir: dir)

    var doc = Scip_Document()
    doc.language = "Swift"
    try cache.saveDocument(doc, relativePath: "test.swift", hash: "testhash")

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

    try cache.saveDocument(doc, relativePath: "test.swift", hash: "recreate")
    try cache.invalidateAll()
    try cache.saveDocument(doc, relativePath: "test.swift", hash: "recreate")
    let loaded = cache.loadDocument(relativePath: "test.swift", hash: "recreate")

    #expect(loaded != nil)
    #expect(loaded?.language == "Swift")
  }

  // MARK: USR side map (D-09 / research Pitfall 3, 02-02)

  @Test("USR side map round-trips under the document's composite key at docs/<composite-key>.usrmap")
  func usrSideMapRoundTrip() throws {
    let dir = makeTempDir()
    let cache = CacheStore(cacheDir: dir)

    let sideMap = [
      "scip-swift swiftpm M . `s:1M4test3fooSSvp`.": "s:1M4test3fooSSvp"
    ]
    try cache.saveUSRMap(sideMap, relativePath: "test.swift", hash: "sidemap")

    let usrmapPath = ((dir as NSString).appendingPathComponent("docs") as NSString)
      .appendingPathComponent(
        "\(CacheStore.documentCacheKey(relativePath: "test.swift", hash: "sidemap")).usrmap")
    #expect(
      FileManager.default.fileExists(atPath: usrmapPath),
      "the side map must live beside its .scipdoc under the same composite key"
    )
    #expect(cache.loadUSRMap(relativePath: "test.swift", hash: "sidemap") == sideMap)
    #expect(
      cache.loadUSRMap(relativePath: "test.swift", hash: "missing") == nil,
      "load failure returns nil and the caller rebuilds (T-02-05)"
    )
  }

  @Test("invalidateAll removes the USR side map with its document (same composite key, atomic)")
  func invalidateAllRemovesUSRMap() throws {
    let dir = makeTempDir()
    let cache = CacheStore(cacheDir: dir)
    try cache.saveUSRMap(["k": "v"], relativePath: "test.swift", hash: "doomed")
    try cache.invalidateAll()
    #expect(
      cache.loadUSRMap(relativePath: "test.swift", hash: "doomed") == nil,
      "side map invalidates with its document"
    )
  }

  @Test("same content hash under two relativePaths yields two distinct, independently loadable entries")
  func sameHashTwoPathsYieldDistinctEntries() throws {
    let dir = makeTempDir()
    let cache = CacheStore(cacheDir: dir)

    var docA = Scip_Document()
    docA.language = "Swift"
    docA.relativePath = "Sources/Pkg/CopyA.swift"
    var docB = Scip_Document()
    docB.language = "Swift"
    docB.relativePath = "Sources/Pkg/CopyB.swift"

    try cache.saveDocument(docA, relativePath: docA.relativePath, hash: "sharedhash")
    try cache.saveDocument(docB, relativePath: docB.relativePath, hash: "sharedhash")

    let keyA = CacheStore.documentCacheKey(relativePath: docA.relativePath, hash: "sharedhash")
    let keyB = CacheStore.documentCacheKey(relativePath: docB.relativePath, hash: "sharedhash")
    #expect(keyA != keyB, "identical content must never collapse two paths onto one key")

    let docsDir = (dir as NSString).appendingPathComponent("docs")
    #expect(
      FileManager.default.fileExists(atPath: (docsDir as NSString).appendingPathComponent("\(keyA).scipdoc")))
    #expect(
      FileManager.default.fileExists(atPath: (docsDir as NSString).appendingPathComponent("\(keyB).scipdoc")))

    let loadedA = cache.loadDocument(relativePath: docA.relativePath, hash: "sharedhash")
    let loadedB = cache.loadDocument(relativePath: docB.relativePath, hash: "sharedhash")
    #expect(loadedA?.relativePath == "Sources/Pkg/CopyA.swift")
    #expect(loadedB?.relativePath == "Sources/Pkg/CopyB.swift")
  }

  private func makeTempDir() -> String {
    let dir = NSTemporaryDirectory() + "cache-test-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
  }
}
