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
      buildToolName: "swiftpm"
    )
    let encoded = try JSONEncoder().encode(manifest)
    let decoded = try JSONDecoder().decode(IndexManifest.self, from: encoded)
    #expect(decoded.toolchainVersion == "6.2.4")
    #expect(decoded.converterVersion == "0.1.2")
    #expect(decoded.indexstoreDbRevision == "c993f4fb")
    #expect(decoded.buildToolName == "swiftpm")
  }

  @Test("isCompatibleWith returns true when all versions match")
  func allVersionsMatch() {
    let manifest = IndexManifest(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D"
    )
    #expect(manifest.isCompatibleWith(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D"))
  }

  @Test("isCompatibleWith returns false when toolchainVersion differs")
  func toolchainMismatch() {
    let manifest = IndexManifest(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D"
    )
    #expect(!manifest.isCompatibleWith(
      toolchainVersion: "X", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D"))
  }

  @Test("isCompatibleWith returns false when converterVersion differs")
  func converterMismatch() {
    let manifest = IndexManifest(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D"
    )
    #expect(!manifest.isCompatibleWith(
      toolchainVersion: "A", converterVersion: "X",
      indexstoreDbRevision: "C", buildToolName: "D"))
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
      buildToolName: BuildTool.swiftpm.rawValue))
  }

  @Test("isCompatibleWith returns false when indexstoreDbRevision differs")
  func revisionMismatch() {
    let manifest = IndexManifest(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D"
    )
    #expect(!manifest.isCompatibleWith(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "X", buildToolName: "D"))
  }

  @Test("isCompatibleWith returns false when buildToolName differs")
  func buildToolMismatch() {
    let manifest = IndexManifest(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "D"
    )
    #expect(!manifest.isCompatibleWith(
      toolchainVersion: "A", converterVersion: "B",
      indexstoreDbRevision: "C", buildToolName: "X"))
  }

  @Test("empty manifest is not compatible with any non-empty version set")
  func emptyManifestIncompatible() {
    let manifest = IndexManifest(
      toolchainVersion: "", converterVersion: "",
      indexstoreDbRevision: "", buildToolName: ""
    )
    #expect(!manifest.isCompatibleWith(
      toolchainVersion: "6.2.4", converterVersion: "0.1.2",
      indexstoreDbRevision: "c993f4fb", buildToolName: "swiftpm"))
  }
}
