import Foundation
import SwiftProtobuf

/// Requirement: INCR-03 (per-file document cache keyed by path + content hash), INCR-01
/// (persistent database path), WR-03 / G-02-2 (02-05 — composite keys).
///
/// File-based per-document protobuf cache. Documents are stored as serialized
/// `Scip_Document` protobufs keyed by the composite (relativePath, content hash) via
/// `documentCacheKey(relativePath:hash:)`. The manifest tracks global version information
/// for cache invalidation.
///
/// Cache directory structure:
///   <cacheDir>/docs/<composite-key>.scipdoc  — serialized Scip_Document files
///   <cacheDir>/manifest.json        — version manifest for global invalidation
struct CacheStore {
  let cacheDir: String

  /// Requirement: WR-03 / G-02-2 (02-05) — cache keys must carry both the file's repo-relative
  /// path and its content hash. Content alone collides for byte-identical files (two sources,
  /// one document — proven by the DuplicateContentFixture); path alone cannot invalidate on
  /// content edits. SHA-256 over `relativePath || 0x00 || hash` (the NUL separator keeps the
  /// concatenation unambiguous). Pre-composite flat `<contentHash>` entries can never match a
  /// derived key; they are reclaimed by the symbolFormatVersion 3 wholesale invalidation, never
  /// migrated.
  static func documentCacheKey(relativePath: String, hash: String) -> String {
    var data = Data(relativePath.utf8)
    data.append(0)
    data.append(Data(hash.utf8))
    return ContentHasher.sha256Hex(of: data)
  }

  private var docsDir: String {
    (cacheDir as NSString).appendingPathComponent("docs")
  }

  private var manifestPath: String {
    (cacheDir as NSString).appendingPathComponent("manifest.json")
  }

  func loadDocument(relativePath: String, hash: String) -> Scip_Document? {
    let key = Self.documentCacheKey(relativePath: relativePath, hash: hash)
    let path = (docsDir as NSString).appendingPathComponent("\(key).scipdoc")
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
    return try? Scip_Document(serializedData: data)
  }

  func saveDocument(_ document: Scip_Document, relativePath: String, hash: String) throws {
    try FileManager.default.createDirectory(
      atPath: docsDir, withIntermediateDirectories: true)
    let key = Self.documentCacheKey(relativePath: relativePath, hash: hash)
    let path = (docsDir as NSString).appendingPathComponent("\(key).scipdoc")
    let data = try document.serializedData()
    try data.write(to: URL(fileURLWithPath: path))
  }

  /// Requirement: SYM-03 / D-09 (02-02) — fail-soft manifest read. A manifest that fails to
  /// decode (e.g. written by an older engine without `symbolFormatVersion`) reads as nil so the
  /// caller takes the fresh-save + wholesale-invalidation path; a decode failure never aborts
  /// indexing.
  func loadManifest() -> IndexManifest? {
    guard FileManager.default.fileExists(atPath: manifestPath) else { return nil }
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)) else { return nil }
    return try? JSONDecoder().decode(IndexManifest.self, from: data)
  }

  func saveManifest(_ manifest: IndexManifest) throws {
    try FileManager.default.createDirectory(
      atPath: cacheDir, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(manifest)
    try data.write(to: URL(fileURLWithPath: manifestPath))
  }

  /// Requirement: SYM-03 / D-09 (02-02, research Pitfall 3) — per-document USR side map
  /// (`docs/<composite-key>.usrmap`): canonicalSymbol -> USR for D-06 fallback symbols,
  /// persisted beside its `.scipdoc` under the same composite key so it invalidates
  /// atomically with the document (T-02-05). Cache-hit runs use it to keep external display
  /// names identical to fresh runs; a load failure returns nil and the caller rebuilds.
  func loadUSRMap(relativePath: String, hash: String) -> [String: String]? {
    let key = Self.documentCacheKey(relativePath: relativePath, hash: hash)
    let path = (docsDir as NSString).appendingPathComponent("\(key).usrmap")
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
    return try? JSONDecoder().decode([String: String].self, from: data)
  }

  func saveUSRMap(_ map: [String: String], relativePath: String, hash: String) throws {
    try FileManager.default.createDirectory(
      atPath: docsDir, withIntermediateDirectories: true)
    let key = Self.documentCacheKey(relativePath: relativePath, hash: hash)
    let path = (docsDir as NSString).appendingPathComponent("\(key).usrmap")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]  // deterministic side-map bytes
    let data = try encoder.encode(map)
    try data.write(to: URL(fileURLWithPath: path))
  }

  /// Removes only this store's own artifacts — `docs/` and `manifest.json`. The cache dir may
  /// also hold the caller's build scratch (`build-scratch/`, `index-db/`), which is owned by the
  /// build step, not the document cache, and must survive invalidation.
  func invalidateAll() throws {
    try? FileManager.default.removeItem(atPath: docsDir)
    try? FileManager.default.removeItem(atPath: manifestPath)
  }
}
