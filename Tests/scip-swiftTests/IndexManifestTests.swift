import Foundation
import Testing

@testable import scip_swift

@Suite("IndexManifest")
struct IndexManifestTests {
  @Test("Codable round-trip preserves all fields")
  func codableRoundTrip() throws {
    let manifest = IndexManifest(
      toolchainVersion: "6.2.4",
      converterVersion: "0.1.2",
      indexstoreDbRevision: "c993f4fb",
      buildToolName: "swiftpm",
      symbolFormatVersion: 2
    )
    let encoded = try JSONEncoder().encode(manifest)
    let decoded = try JSONDecoder().decode(IndexManifest.self, from: encoded)
    #expect(decoded.toolchainVersion == "6.2.4")
    #expect(decoded.converterVersion == "0.1.2")
    #expect(decoded.indexstoreDbRevision == "c993f4fb")
    #expect(decoded.buildToolName == "swiftpm")
    #expect(decoded.symbolFormatVersion == 2)
  }

  @Test("isCompatibleWith returns true when all versions match")
  func allVersionsMatch() {
    let manifest = IndexManifest(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D",
      symbolFormatVersion: 2
    )
    #expect(manifest.isCompatibleWith(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D",
      symbolFormatVersion: 2,
      demangle: true))
  }

  @Test("isCompatibleWith returns false when toolchainVersion differs")
  func toolchainMismatch() {
    let manifest = IndexManifest(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D",
      symbolFormatVersion: 2
    )
    #expect(!manifest.isCompatibleWith(
      toolchainVersion: "X", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D",
      symbolFormatVersion: 2,
      demangle: true))
  }

  @Test("isCompatibleWith returns false when converterVersion differs")
  func converterMismatch() {
    let manifest = IndexManifest(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D",
      symbolFormatVersion: 2
    )
    #expect(!manifest.isCompatibleWith(
      toolchainVersion: "A", converterVersion: "X",
      indexstoreDbRevision: "C", buildToolName: "D",
      symbolFormatVersion: 2,
      demangle: true))
  }

  @Test("manifest written by converter 0.2.1 is incompatible with the current version constant")
  func converterVersionBumpInvalidatesOldCache() {
    let manifest = IndexManifest(
      toolchainVersion: ToolchainInfo.pinnedSwiftVersion,
      converterVersion: "0.2.1",
      indexstoreDbRevision: IndexCommand.indexstoreDbRevision,
      buildToolName: BuildTool.swiftpm.rawValue
    )
    #expect(!manifest.isCompatibleWith(
      toolchainVersion: ToolchainInfo.pinnedSwiftVersion,
      converterVersion: ScipSwiftVersion.version,
      indexstoreDbRevision: IndexCommand.indexstoreDbRevision,
      buildToolName: BuildTool.swiftpm.rawValue,
      symbolFormatVersion: SymbolFormatVersion.current,
      demangle: true))
  }

  @Test("isCompatibleWith returns false when indexstoreDbRevision differs")
  func revisionMismatch() {
    let manifest = IndexManifest(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D",
      symbolFormatVersion: 2
    )
    #expect(!manifest.isCompatibleWith(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "X", buildToolName: "D",
      symbolFormatVersion: 2,
      demangle: true))
  }

  @Test("isCompatibleWith returns false when buildToolName differs")
  func buildToolMismatch() {
    let manifest = IndexManifest(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D",
      symbolFormatVersion: 2
    )
    #expect(!manifest.isCompatibleWith(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "X",
      symbolFormatVersion: 2,
      demangle: true))
  }

  @Test("empty manifest is not compatible with any non-empty version set")
  func emptyManifestIncompatible() {
    let manifest = IndexManifest(
      toolchainVersion: "", converterVersion: "",
      indexstoreDbRevision: "", buildToolName: "",
      symbolFormatVersion: 2
    )
    #expect(!manifest.isCompatibleWith(
      toolchainVersion: "6.2.4", converterVersion: "0.1.2",
      indexstoreDbRevision: "c993f4fb", buildToolName: "swiftpm",
      symbolFormatVersion: 2,
      demangle: true))
  }

  // MARK: symbolFormatVersion gating (D-09, 02-02)

  @Test("symbolFormatVersion mismatch wholesale-invalidates: manifest at N is incompatible with reader at N+1")
  func symbolFormatVersionMismatch() {
    let manifest = IndexManifest(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D",
      symbolFormatVersion: 1
    )
    #expect(!manifest.isCompatibleWith(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D",
      symbolFormatVersion: 2,
      demangle: true))
    #expect(manifest.isCompatibleWith(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D",
      symbolFormatVersion: 1,
      demangle: true))
  }

  @Test("the format constant is 4 — import-role occurrences + test-target marking (03-03)")
  func formatConstantIsCurrent() {
    #expect(SymbolFormatVersion.current == 4)
  }

  @Test("old manifest without symbolFormatVersion fails decode — decode failure means invalidation (D-09)")
  func legacyManifestWithoutFormatVersionFailsDecode() throws {
    let legacyJSON =
      #"{"toolchainVersion":"6.2.4","converterVersion":"0.2.1","indexstoreDbRevision":"c993f4fb","buildToolName":"swiftpm"}"#
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(IndexManifest.self, from: Data(legacyJSON.utf8))
    }
  }

  @Test("CacheStore.loadManifest treats an undecodable legacy manifest as absent (fresh-save path)")
  func loadManifestIsFailSoftOnUndecodableLegacy() throws {
    let cacheDir = NSTemporaryDirectory() + "manifest-legacy-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
    let manifestPath = (cacheDir as NSString).appendingPathComponent("manifest.json")
    let legacyJSON =
      #"{"toolchainVersion":"6.2.4","converterVersion":"0.2.1","indexstoreDbRevision":"c993f4fb","buildToolName":"swiftpm"}"#
    try Data(legacyJSON.utf8).write(to: URL(fileURLWithPath: manifestPath))

    let store = CacheStore(cacheDir: cacheDir)
    #expect(
      store.loadManifest() == nil,
      "undecodable manifest must read as no-manifest so the caller falls into the fresh-save wholesale-invalidation path"
    )
  }

  // MARK: overload-table fingerprint (D-09 / T-02-04, 02-02 Task 3)

  @Test("manifest round-trips overloadTableFingerprint")
  func overloadFingerprintRoundTrip() throws {
    let manifest = IndexManifest(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D",
      overloadTableFingerprint: "deadbeef"
    )
    let encoded = try JSONEncoder().encode(manifest)
    let decoded = try JSONDecoder().decode(IndexManifest.self, from: encoded)
    #expect(decoded.overloadTableFingerprint == "deadbeef")
  }

  @Test("isCompatibleWith deliberately ignores the overload fingerprint — the index builder owns that dynamic key")
  func compatibilityIgnoresOverloadFingerprint() {
    // The fingerprint depends on the opened store, which IndexCommand cannot know before the
    // build; SCIPIndexBuilder validates it right after its definitions pre-pass.
    let manifest = IndexManifest(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D",
      overloadTableFingerprint: "old-fingerprint"
    )
    #expect(manifest.isCompatibleWith(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D",
      symbolFormatVersion: SymbolFormatVersion.current,
      demangle: true))
  }

  @Test("old manifest without overloadTableFingerprint fails decode (strict schema, D-09)")
  func legacyManifestWithoutFingerprintFailsDecode() throws {
    let legacyJSON =
      #"{"toolchainVersion":"6.2.4","converterVersion":"0.2.1","indexstoreDbRevision":"c993f4fb","buildToolName":"swiftpm","symbolFormatVersion":2}"#
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(IndexManifest.self, from: Data(legacyJSON.utf8))
    }
  }

  @Test("old manifest without packageManifestFingerprint fails decode (strict schema, CR-01)")
  func legacyManifestWithoutPackageFingerprintFailsDecode() throws {
    // Every key the pre-CR-01 engine wrote is present — packageManifestFingerprint is
    // the ONLY missing field, so decode failure isolates the new schema requirement.
    let legacyJSON =
      #"{"toolchainVersion":"6.2.4","converterVersion":"0.2.1","indexstoreDbRevision":"c993f4fb","buildToolName":"swiftpm","symbolFormatVersion":4,"overloadTableFingerprint":"abc","demangle":true}"#
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(IndexManifest.self, from: Data(legacyJSON.utf8))
    }
  }

  @Test("demangle mode mismatch invalidates the cache (W2 — display names differ per mode)")
  func demangleModeIsACompatibilityKey() {
    let demangledCache = IndexManifest(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D",
      symbolFormatVersion: SymbolFormatVersion.current,
      demangle: true
    )
    #expect(!demangledCache.isCompatibleWith(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D",
      symbolFormatVersion: SymbolFormatVersion.current,
      demangle: false))
    #expect(demangledCache.isCompatibleWith(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D",
      symbolFormatVersion: SymbolFormatVersion.current,
      demangle: true))
  }
}
