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
///     format 2 is the canonical descriptor-chain scheme; format 3 keys cached documents by
///     the composite (relativePath, content hash) instead of content hash alone (02-05). A
///     bump wholesale-invalidates cached documents so old-format caches never mix with
///     new-format output.
///   - overloadTableFingerprint: SHA-256 over the overload table's groups and their
///     source-ordered member USRs (D-10 / T-02-04, 02-02 Task 3). NOT compared by
///     `isCompatibleWith` — it depends on the opened index store, which the caller cannot
///     know before the build; `SCIPIndexBuilder` validates it right after its definitions
///     pre-pass, and any change wholesale-invalidates cached documents.
///   - packageManifestFingerprint: SHA-256 over the indexed repo's Package.swift bytes
///     ("" when absent) — CR-01 (03 review). From format 4 the emitted document bytes
///     depend on `PackageTargetMap` (NAV-03 Test bits, SYM-04 import manager forms), so
///     a manifest-only edit that leaves every source hash and definition USR identical
///     (e.g. `.target` → `.testTarget` with the path pinned) would otherwise serve stale
///     cached documents forever. Raw bytes (not a derived-map digest) so path edits the
///     map normalizes away also invalidate. Decodes NON-optionally: a manifest written
///     before the field existed fails decode, reads as no-manifest, and the caller takes
///     the fresh-save + wholesale-invalidation path (same strict-schema choice as
///     symbolFormatVersion). Like overloadTableFingerprint it is not knowable inside the
///     builder's default init, so it defaults to "" there — IndexCommand computes and
///     validates the real hash.
struct IndexManifest: Codable {
  var toolchainVersion: String
  var converterVersion: String
  var indexstoreDbRevision: String
  var buildToolName: String
  var symbolFormatVersion: Int
  var overloadTableFingerprint: String
  var demangle: Bool
  var packageManifestFingerprint: String

  init(
    toolchainVersion: String,
    converterVersion: String,
    indexstoreDbRevision: String,
    buildToolName: String,
    symbolFormatVersion: Int = SymbolFormatVersion.current,
    overloadTableFingerprint: String = "",
    demangle: Bool = true,
    packageManifestFingerprint: String = ""
  ) {
    self.toolchainVersion = toolchainVersion
    self.converterVersion = converterVersion
    self.indexstoreDbRevision = indexstoreDbRevision
    self.buildToolName = buildToolName
    self.symbolFormatVersion = symbolFormatVersion
    self.overloadTableFingerprint = overloadTableFingerprint
    self.demangle = demangle
    self.packageManifestFingerprint = packageManifestFingerprint
  }

  func isCompatibleWith(
    toolchainVersion: String,
    converterVersion: String,
    indexstoreDbRevision: String,
    buildToolName: String,
    symbolFormatVersion: Int,
    demangle: Bool,
    packageManifestFingerprint: String
  ) -> Bool {
    self.toolchainVersion == toolchainVersion
      && self.converterVersion == converterVersion
      && self.indexstoreDbRevision == indexstoreDbRevision
      && self.buildToolName == buildToolName
      && self.symbolFormatVersion == symbolFormatVersion
      && self.demangle == demangle
      && self.packageManifestFingerprint == packageManifestFingerprint
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
  /// descriptor-chain scheme (02-01) with canonical ordering/dedup and the USR side map (02-02);
  /// format 3 keys cached documents by the composite (relativePath, content hash) —
  /// `CacheStore.documentCacheKey` — so byte-identical files never share an entry (02-05 /
  /// G-02-2). Derived keys never match a format-2 flat content-hash file, so the bump reclaims
  /// those caches wholesale via the existing manifest gate instead of orphaning them.
  /// Format 4 (03-03) changes emitted occurrence bytes: written imports emit Import-role
  /// occurrences resolving to module symbols (`c:@M@` USRs parse; the D-06 fallback Terms
  /// for them vanish), and every occurrence in a test-target document carries the Test bit.
  /// A bump wholesale-invalidates format-3 caches via the same manifest gate.
  static let current = 4
}
