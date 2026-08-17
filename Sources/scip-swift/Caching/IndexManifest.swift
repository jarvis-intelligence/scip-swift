import Foundation

/// Requirement: INCR-06 (cache invalidation on toolchain/indexstore-db/scip-swift version
/// change), SYM-03 / D-09 (02-02 — symbol-format version invalidation).
///
/// Global cache invalidation: any version mismatch means the entire cache is stale and must be
/// rebuilt. The fields are:
///   - toolchainVersion: Swift compiler version (USR format is compiler-version sensitive)
///   - converterVersion: scip-swift version (mapping logic changes)
///   - indexstoreDbRevision: indexstore-db git revision (store format changes)
///   - buildToolName: "swiftpm" or "xcodebuild" (different index data)
///   - symbolFormatVersion: emitted symbol-string format (D-09). Format 1 is the raw-USR era;
///     format 2 is the canonical descriptor-chain scheme. A bump wholesale-invalidates cached
///     documents so old-format caches never mix with new-format output.
struct IndexManifest: Codable {
  var toolchainVersion: String
  var converterVersion: String
  var indexstoreDbRevision: String
  var buildToolName: String
  var symbolFormatVersion: Int

  init(
    toolchainVersion: String,
    converterVersion: String,
    indexstoreDbRevision: String,
    buildToolName: String,
    symbolFormatVersion: Int = SymbolFormatVersion.current
  ) {
    self.toolchainVersion = toolchainVersion
    self.converterVersion = converterVersion
    self.indexstoreDbRevision = indexstoreDbRevision
    self.buildToolName = buildToolName
    self.symbolFormatVersion = symbolFormatVersion
  }

  func isCompatibleWith(
    toolchainVersion: String,
    converterVersion: String,
    indexstoreDbRevision: String,
    buildToolName: String,
    symbolFormatVersion: Int
  ) -> Bool {
    self.toolchainVersion == toolchainVersion
      && self.converterVersion == converterVersion
      && self.indexstoreDbRevision == indexstoreDbRevision
      && self.buildToolName == buildToolName
      && self.symbolFormatVersion == symbolFormatVersion
  }
}

/// Requirement: SYM-03 / D-09 (02-02). The emitted symbol-string format version.
///
/// The manifest decodes `symbolFormatVersion` NON-optionally: a manifest written by an older
/// engine (no such key) fails decode, `CacheStore.loadManifest` reads that as no-manifest, and
/// the caller falls into the fresh-save + wholesale-invalidate path. Both decode shapes are
/// safe; this one needs no migration code (the explicit choice of plan 02-02).
enum SymbolFormatVersion {
  /// Format 1 is the raw-USR era (escaped USR term descriptors); format 2 is the canonical
  /// descriptor-chain scheme (02-01) with canonical ordering/dedup and the USR side map (02-02).
  static let current = 2
}
