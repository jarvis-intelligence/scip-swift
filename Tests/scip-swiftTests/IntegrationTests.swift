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

    // Exact-range tracer (RANGE-01): the getter:name occurrences anchor at token `name` — the
    // property definition on `  public let name: String` (line 2) has exact extent [13,17),
    // where the display-name approximation would have produced 24 (+7 drift, research F3a).
    // The interpolation use on line 9 (`\(name)`) has exact extent [14,18).
    let getterUSR = "s:16MiniSwiftPackage7GreeterV4nameSSvg"
    let getterNameRanges = document.occurrences
      .filter { $0.symbol.contains(getterUSR) }
      .map(\.singleLineRange)
    #expect(!getterNameRanges.isEmpty, "fixture must emit at least one getter:name occurrence")
    #expect(
      getterNameRanges.contains { $0.line == 1 && $0.startCharacter == 13 && $0.endCharacter == 17 },
      "getter:name on the property definition must carry the exact token extent [13,17), not the approximate 24"
    )
    #expect(
      getterNameRanges.contains { $0.line == 8 && $0.startCharacter == 14 && $0.endCharacter == 18 },
      "getter:name inside the string interpolation must carry the exact token extent [14,18)"
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

  @Test("external symbols carry demangled display names when demangle is on")
  func externalSymbolsCarryDemangledNamesWhenDemangleOn() throws {
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
      converterVersion: "test"
    )
    let index = try builder.build()

    #expect(!index.externalSymbols.isEmpty)
    let displayNames = index.externalSymbols.map(\.displayName)
    #expect(
      displayNames.contains { $0.contains("Swift.String") },
      "stdlib String references should carry demangled external display names"
    )

    let demangler = try #require(USRDemangler.load())
    for external in index.externalSymbols {
      let expected = displayNamesSafeDemangle(demangler, external.symbol)
      if let expected {
        #expect(
          external.displayName == expected,
          "external whose USR demangles must not be empty: \(external.symbol)"
        )
      }
    }

    let symbols = index.externalSymbols.map(\.symbol)
    #expect(symbols == symbols.sorted(), "external symbol ordering must be unchanged")
  }

  private func displayNamesSafeDemangle(_ demangler: USRDemangler, _ canonicalSymbol: String) -> String? {
    guard let usr = Self.usrFromCanonicalSymbolString(canonicalSymbol) else { return nil }
    return demangler.demangledDisplayName(usr: usr)
  }

  private static func usrFromCanonicalSymbolString(_ symbolString: String) -> String? {
    guard let separator = symbolString.lastIndex(of: " ") else { return nil }
    let descriptor = symbolString[separator...].dropFirst()
    guard descriptor.hasSuffix(".") else { return nil }
    let body = descriptor.dropLast()
    if body.hasPrefix("`"), body.hasSuffix("`") {
      return String(body.dropFirst().dropLast()).replacingOccurrences(of: "``", with: "`")
    }
    return String(body)
  }

  @Test("Unicode fixture emits the hand-computed F4 range table")
  func unicodeFixtureEmitsHandComputedF4RangeTable() throws {
    let fixtureRepoPath = Self.unicodeFixtureRepoPath()
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

    let document = try #require(
      index.documents.first { $0.relativePath == "Sources/UnicodeRange/main.swift" }
    )
    #expect(!document.occurrences.isEmpty)

    // F4 (research §Key Verified Facts): 0-based UTF-8 byte columns, hand-computed against the
    // fixture's exact bytes. Getters ride on their accessor USRs (`vg` suffix), definitions on
    // `vp` — the getter rows are the load-bearing drift proof, so they must be symbol-linked:
    // the plain `emoji`/`名前` definitions would pass even under the display-name approximation.
    func expectRow(
      _ symbolFragment: String, _ line: Int32, _ start: Int32, _ end: Int32, _ what: String
    ) {
      let rows = document.occurrences
        .filter { $0.symbol.contains(symbolFragment) }
        .map(\.singleLineRange)
      #expect(!rows.isEmpty, "fixture must emit \(what) occurrences")
      #expect(
        rows.contains { $0.line == line && $0.startCharacter == start && $0.endCharacter == end },
        "\(what) must carry the F4 range [\(start),\(end)) on line \(line)"
      )
    }

    expectRow("5emojiSSvp", 0, 4, 9, "emoji definition")
    expectRow("5emojiSSvg", 0, 4, 9, "getter:emoji")
    expectRow("6名前SSvp", 1, 4, 10, "名前 definition")
    expectRow("6名前SSvg", 1, 4, 10, "getter:名前")
    expectRow("5greet", 1, 13, 18, "greet reference")
    expectRow("5greet", 3, 5, 10, "greet definition")
    expectRow("4name", 3, 11, 15, "name parameter definition")
    expectRow("s:SS", 3, 17, 23, "first String reference")
    expectRow("s:SS", 3, 28, 34, "second String reference")
    expectRow("stringInterpolation", 4, 2, 3, "init(stringInterpolation:)")
    expectRow("4name", 4, 12, 16, "name reference inside the interpolation")

    let allRanges = document.occurrences.map(\.singleLineRange)
    #expect(
      allRanges.contains { $0.line == 4 && $0.startCharacter == 12 && $0.endCharacter == 16 },
      "F4 name-ref row must be present even if it rides on a local symbol"
    )

    // Drift proofs (RANGE-01): with the refiner removed these accessor rows would fall back to
    // the display-name approximation — end 16 for `getter:emoji` (7-byte prefix overshoot) and
    // 17 for `getter:名前` (13-byte overshoot). Asserting exactness, not equality with old output.
    let getterEmojiEnds = document.occurrences
      .filter { $0.symbol.contains("5emojiSSvg") }
      .map(\.singleLineRange)
    #expect(
      !getterEmojiEnds.contains { $0.line == 0 && $0.startCharacter == 4 && $0.endCharacter == 16 },
      "getter:emoji must not carry the approximate end 16 — the exact token end is 9"
    )
    let getterMeiEnds = document.occurrences
      .filter { $0.symbol.contains("6名前SSvg") }
      .map(\.singleLineRange)
    #expect(
      !getterMeiEnds.contains { $0.line == 1 && $0.startCharacter == 4 && $0.endCharacter == 17 },
      "getter:名前 must not carry the approximate end 17 — the exact token end is 10"
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

  static func unicodeFixtureRepoPath() -> String {
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return repoRoot.appendingPathComponent("Fixtures/UnicodeRangeFixture").path
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
