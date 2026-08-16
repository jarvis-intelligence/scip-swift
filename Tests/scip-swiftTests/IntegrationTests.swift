import Foundation
import Testing

@testable import scip_swift

/// Requirement: run the full pipeline (build → IndexStore → SCIP) against a small real Swift
/// fixture repo (task 4.4). This actually shells out to `swift build`, so it's slower than the
/// unit tests but exercises real behavior end-to-end, per project convention (no mocks).
@Suite("Integration: build -> IndexStore -> SCIP")
struct IntegrationTests {
  @Test("full pipeline produces a valid SCIP index for the fixture package")
  func fullPipeline() throws {
    let fixtureRepoPath = Self.fixtureRepoPath()
    let fixtureBuildPath = (fixtureRepoPath as NSString).appendingPathComponent(".build")
    defer { try? FileManager.default.removeItem(atPath: fixtureBuildPath) }

    let workDirectory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(atPath: workDirectory) }

    let runner = SwiftPMBuildRunner(
      repoPath: fixtureRepoPath,
      configuration: .debug,
      scratchPath: (workDirectory as NSString).appendingPathComponent("scratch")
    )
    let buildResult = try runner.produceIndexStore()

    let builder = SCIPIndexBuilder(
      repoPath: fixtureRepoPath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: (workDirectory as NSString).appendingPathComponent("index-db"),
      buildToolName: BuildTool.swiftpm.rawValue,
      converterVersion: "test"
    )
    let index = try builder.build()

    #expect(index.documents.count == 1)
    let document = try #require(index.documents.first)
    #expect(document.relativePath == "Sources/MiniSwiftPackage/Greeter.swift")
    #expect(document.language == "Swift")
    #expect(!document.occurrences.isEmpty)

    let displayNames = Set(document.symbols.map(\.displayName))
    #expect(displayNames.contains("MiniSwiftPackage.Greeter"), "struct Greeter should be demangled")
    #expect(
      displayNames.contains("MiniSwiftPackage.Greeter.greet() -> Swift.String"),
      "greet() should be demangled"
    )

    let greetSymbol = try #require(
      document.symbols.first { $0.displayName == "MiniSwiftPackage.Greeter.greet() -> Swift.String" }
    )
    #expect(
      greetSymbol.symbol == "scip-swift swiftpm MiniSwiftPackage . `s:16MiniSwiftPackage7GreeterV5greetSSyF`.",
      "canonical symbol string must still embed the raw USR verbatim"
    )

    #expect(index.metadata.toolInfo.name == "scip-swift")
  }

  @Test("demangle off reproduces v0.2.x opaque display names")
  func demangleOffReproducesV02xDisplayNames() throws {
    let fixtureRepoPath = Self.fixtureRepoPath()
    let workDirectory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(atPath: workDirectory) }

    let runner = SwiftPMBuildRunner(
      repoPath: fixtureRepoPath,
      configuration: .debug,
      scratchPath: (workDirectory as NSString).appendingPathComponent("scratch")
    )
    let buildResult = try runner.produceIndexStore()

    let builder = SCIPIndexBuilder(
      repoPath: fixtureRepoPath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: (workDirectory as NSString).appendingPathComponent("index-db"),
      buildToolName: BuildTool.swiftpm.rawValue,
      converterVersion: "test",
      demangle: false
    )
    let index = try builder.build()

    let document = try #require(index.documents.first)
    let displayNames = Set(document.symbols.map(\.displayName))
    #expect(displayNames.contains("Greeter"), "v0.2.x parity: short struct name")
    #expect(displayNames.contains("greet()"), "v0.2.x parity: short method name")
    #expect(displayNames.contains("name"), "v0.2.x parity: short property name")
    #expect(
      !displayNames.contains("MiniSwiftPackage.Greeter"),
      "demangled names must not appear with demangling off"
    )
  }

  @Test("external symbols stay empty when demangle is off")
  func externalSymbolsStayEmptyWhenDemangleOff() throws {
    let fixtureRepoPath = Self.fixtureRepoPath()
    let workDirectory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(atPath: workDirectory) }

    let runner = SwiftPMBuildRunner(
      repoPath: fixtureRepoPath,
      configuration: .debug,
      scratchPath: (workDirectory as NSString).appendingPathComponent("scratch")
    )
    let buildResult = try runner.produceIndexStore()

    let builder = SCIPIndexBuilder(
      repoPath: fixtureRepoPath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: (workDirectory as NSString).appendingPathComponent("index-db"),
      buildToolName: BuildTool.swiftpm.rawValue,
      converterVersion: "test",
      demangle: false
    )
    let index = try builder.build()

    #expect(!index.externalSymbols.isEmpty, "fixture must reference at least one external symbol (String)")
    #expect(
      index.externalSymbols.allSatisfy { $0.displayName.isEmpty },
      "v0.2.x parity: external symbols carry no display names when demangling is off"
    )
  }

  @Test("index --help advertises --no-demangle")
  func helpListsNoDemangleFlag() throws {
    let result = try SubprocessRunner.run(
      executable: Self.builtBinaryPath(),
      arguments: ["index", "--help"],
      currentDirectory: "/"
    )
    #expect(result.combinedOutput.contains("--no-demangle"))
  }

  private static func fixtureRepoPath() -> String {
    // Tests/scip-swiftTests/IntegrationTests.swift -> repo root
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return repoRoot.appendingPathComponent("Fixtures/MiniSwiftPackage").path
  }

  private static func makeTemporaryDirectory() throws -> String {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("scip-swift-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }

  private static func builtBinaryPath() -> String {
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return repoRoot.appendingPathComponent(".build/debug/scip-swift").path
  }
}
