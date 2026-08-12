import Foundation

/// Requirement: INCR-06 (cache invalidation on toolchain/indexstore-db/scip-swift version change).
///
/// Four-layer global cache invalidation: any version mismatch means the entire cache
/// is stale and must be rebuilt. The four fields are:
///   - toolchainVersion: Swift compiler version (USR format is compiler-version sensitive)
///   - converterVersion: scip-swift version (mapping logic changes)
///   - indexstoreDbRevision: indexstore-db git revision (store format changes)
///   - buildToolName: "swiftpm" or "xcodebuild" (different index data)
struct IndexManifest: Codable {
  var toolchainVersion: String
  var converterVersion: String
  var indexstoreDbRevision: String
  var buildToolName: String

  func isCompatibleWith(
    toolchainVersion: String,
    converterVersion: String,
    indexstoreDbRevision: String,
    buildToolName: String
  ) -> Bool {
    self.toolchainVersion == toolchainVersion
      && self.converterVersion == converterVersion
      && self.indexstoreDbRevision == indexstoreDbRevision
      && self.buildToolName == buildToolName
  }
}
