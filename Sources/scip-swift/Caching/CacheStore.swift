import Foundation
import SwiftProtobuf

/// Requirement: INCR-03 (per-file document cache keyed by content hash), INCR-01 (persistent database path).
///
/// File-based per-document protobuf cache. Documents are stored as serialized
/// `Scip_Document` protobufs keyed by SHA256 content hash. The manifest tracks
/// global version information for cache invalidation.
///
/// Cache directory structure:
///   <cacheDir>/docs/<hash>.scipdoc  — serialized Scip_Document files
///   <cacheDir>/manifest.json        — version manifest for global invalidation
struct CacheStore {
  let cacheDir: String

  private var docsDir: String {
    (cacheDir as NSString).appendingPathComponent("docs")
  }

  private var manifestPath: String {
    (cacheDir as NSString).appendingPathComponent("manifest.json")
  }

  func loadDocument(hash: String) -> Scip_Document? {
    let path = (docsDir as NSString).appendingPathComponent("\(hash).scipdoc")
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
    return try? Scip_Document(serializedData: data)
  }

  func saveDocument(_ document: Scip_Document, hash: String) throws {
    try FileManager.default.createDirectory(
      atPath: docsDir, withIntermediateDirectories: true)
    let path = (docsDir as NSString).appendingPathComponent("\(hash).scipdoc")
    let data = try document.serializedData()
    try data.write(to: URL(fileURLWithPath: path))
  }

  func loadManifest() throws -> IndexManifest? {
    guard FileManager.default.fileExists(atPath: manifestPath) else { return nil }
    let data = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
    return try JSONDecoder().decode(IndexManifest.self, from: data)
  }

  func saveManifest(_ manifest: IndexManifest) throws {
    try FileManager.default.createDirectory(
      atPath: cacheDir, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(manifest)
    try data.write(to: URL(fileURLWithPath: manifestPath))
  }

  /// Removes only this store's own artifacts — `docs/` and `manifest.json`. The cache dir may
  /// also hold the caller's build scratch (`build-scratch/`, `index-db/`), which is owned by the
  /// build step, not the document cache, and must survive invalidation.
  func invalidateAll() throws {
    try? FileManager.default.removeItem(atPath: docsDir)
    try? FileManager.default.removeItem(atPath: manifestPath)
  }
}
