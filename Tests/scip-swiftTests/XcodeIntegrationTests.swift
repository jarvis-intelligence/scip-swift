import Foundation
import Testing

@testable import scip_swift

/// Requirement: TEST-01 — end-to-end integration test for the Xcode build path
/// (XcodebuildBuildRunner -> IndexStore -> SCIPIndexBuilder). Shells out to a real `xcodebuild`
/// against `Fixtures/XcodeTestProject`, so it's slower than the unit tests but exercises real
/// behavior end-to-end, per project convention (no mocks).
@Suite("Xcode Integration")
struct XcodeIntegrationTests {
  @Test("full Xcode pipeline produces a valid SCIP index for the fixture project")
  func fullPipeline() throws {
    let fixtureRepoPath = Self.fixtureRepoPath()
    let workDirectory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(atPath: workDirectory) }

    let projectArguments = try XcodeProjectLocator.workspaceOrProjectArguments(repoPath: fixtureRepoPath)
    let scheme = try XcodeProjectLocator.resolveScheme(
      explicitScheme: nil,
      projectArguments: projectArguments,
      repoPath: fixtureRepoPath
    )

    let derivedDataPath = (workDirectory as NSString).appendingPathComponent("DerivedData")
    let runner = XcodebuildBuildRunner(
      repoPath: fixtureRepoPath,
      configuration: .debug,
      scheme: scheme,
      derivedDataPath: derivedDataPath,
      projectArguments: projectArguments
    )
    let buildResult = try runner.produceIndexStore()

    let builder = SCIPIndexBuilder(
      repoPath: fixtureRepoPath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: (workDirectory as NSString).appendingPathComponent("index-db"),
      buildToolName: BuildTool.xcodebuild.rawValue,
      converterVersion: "test"
    )
    let index = try builder.build()

    #expect(index.documents.count > 0)
    let document = try #require(index.documents.first)
    #expect(document.language == "Swift")
    #expect(!document.symbols.isEmpty)
  }

  @Test("indexOneRepo builds an Xcode fixture through the xcodebuild backend")
  func indexOneRepoDispatchesXcodeFixtures() throws {
    let index = try IndexCommand.indexOneRepo(
      repoPath: Self.fixtureRepoPath(),
      output: nil,
      buildTool: nil,
      configuration: .debug,
      scheme: nil,
      cacheDir: nil,
      indexOnly: false,
      symbolVersion: ""
    )

    #expect(index.documents.count > 0)
    let document = try #require(index.documents.first)
    #expect(document.language == "Swift")
    #expect(!document.symbols.isEmpty)
  }

  @Test("indexOneRepo with --cache-dir also builds an Xcode fixture through xcodebuild")
  func indexOneRepoDispatchesXcodeFixturesThroughCache() throws {
    let cacheDir = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(atPath: cacheDir) }

    let index = try IndexCommand.indexOneRepo(
      repoPath: Self.fixtureRepoPath(),
      output: nil,
      buildTool: nil,
      configuration: .debug,
      scheme: nil,
      cacheDir: cacheDir,
      indexOnly: false,
      symbolVersion: ""
    )

    #expect(index.documents.count > 0)
    let derivedDataPath = (cacheDir as NSString).appendingPathComponent("derived-data")
    #expect(FileManager.default.fileExists(atPath: derivedDataPath))
  }

  @Test("explicit destination builds the fixture and produces an index")
  func explicitDestinationBuildsFixture() throws {
    let index = try IndexCommand.indexOneRepo(
      repoPath: Self.fixtureRepoPath(),
      output: nil,
      buildTool: nil,
      configuration: .debug,
      scheme: nil,
      destination: "platform=macOS",
      cacheDir: nil,
      indexOnly: false,
      symbolVersion: ""
    )

    #expect(index.documents.count > 0)
    let document = try #require(index.documents.first)
    #expect(document.language == "Swift")
    #expect(!document.symbols.isEmpty)
  }

  @Test("bogus destination fails with the discoverable hint")
  func bogusDestinationFailsWithHint() throws {
    do {
      _ = try IndexCommand.indexOneRepo(
        repoPath: Self.fixtureRepoPath(),
        output: nil,
        buildTool: nil,
        configuration: .debug,
        scheme: nil,
        destination: "platform=iOS Simulator,name=Nonexistent Device 999",
        cacheDir: nil,
        indexOnly: false,
        symbolVersion: ""
      )
      Issue.record("expected a bogus destination to fail the build")
    } catch {
      let description = String(describing: error)
      #expect(description.contains("-showdestinations"))
      #expect(
        description.contains(
          "Unable to find a device matching the provided destination specifier:"
        )
      )
    }
  }

  private static func fixtureRepoPath() -> String {
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return repoRoot.appendingPathComponent("Fixtures/XcodeTestProject").path
  }

  private static func makeTemporaryDirectory() throws -> String {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("scip-swift-xcode-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }
}
