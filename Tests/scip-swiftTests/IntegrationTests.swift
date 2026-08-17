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

  @Test("canonical descriptor symbols replace raw USRs end-to-end")
  func canonicalSymbolsReplaceRawUSRs() throws {
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

    let document = try #require(
      index.documents.first { $0.relativePath == "Sources/MiniSwiftPackage/Greeter.swift" }
    )
    let occurrenceSymbols = Set(document.occurrences.map(\.symbol))
    let definedSymbols = Set(document.symbols.map(\.symbol))

    // The frozen Phase-1 scheme (SYM-03): descriptor chains, not escaped USRs. The struct is a
    // Type descriptor (`Greeter#`), the method a Method descriptor (`greet().`).
    #expect(
      occurrenceSymbols.contains("scip-swift swiftpm MiniSwiftPackage . Greeter#"),
      "Greeter struct definition/reference must carry the canonical Type descriptor symbol"
    )
    #expect(
      occurrenceSymbols.contains("scip-swift swiftpm MiniSwiftPackage . Greeter#greet()."),
      "greet method must carry the canonical Method descriptor symbol"
    )
    #expect(
      definedSymbols.contains("scip-swift swiftpm MiniSwiftPackage . Greeter#"),
      "Greeter must have a SymbolInformation under its canonical symbol string"
    )
    #expect(
      definedSymbols.contains("scip-swift swiftpm MiniSwiftPackage . Greeter#greet()."),
      "greet must have a SymbolInformation under its canonical symbol string"
    )
    #expect(
      !occurrenceSymbols.contains { $0.contains("s:16MiniSwiftPackage7GreeterV") },
      "no Greeter occurrence may embed the raw USR once the canonical scheme is wired"
    )
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
    // Swift mangles the non-ASCII identifier 名前 as `006ldrIFb` inside the USR.
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
    expectRow("006ldrIFbSSvp", 1, 4, 10, "名前 definition")
    expectRow("006ldrIFbSSvg", 1, 4, 10, "getter:名前")
    expectRow("5greet", 1, 13, 18, "greet reference")
    expectRow("5greet", 3, 5, 10, "greet definition")
    expectRow("ACL_SSvp", 3, 11, 15, "name parameter definition")
    expectRow("s:SS", 3, 17, 23, "first String reference")
    expectRow("s:SS", 3, 28, 34, "second String reference")
    expectRow("stringInterpolation", 4, 2, 3, "init(stringInterpolation:)")
    expectRow("ACL_SSvp", 4, 12, 16, "name reference inside the interpolation")

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
      .filter { $0.symbol.contains("006ldrIFbSSvg") }
      .map(\.singleLineRange)
    #expect(
      !getterMeiEnds.contains { $0.line == 1 && $0.startCharacter == 4 && $0.endCharacter == 17 },
      "getter:名前 must not carry the approximate end 17 — the exact token end is 10"
    )
  }

  @Test("source with syntax errors still indexes with exact ends on valid regions")
  func brokenSourceStillIndexesWithExactEnds() throws {
    let fixtureRepoPath = Self.brokenSourceFixtureRepoPath()
    let fixtureBuildPath = (fixtureRepoPath as NSString).appendingPathComponent(".build")
    defer { try? FileManager.default.removeItem(atPath: fixtureBuildPath) }

    let sourcePath = (fixtureRepoPath as NSString)
      .appendingPathComponent("Sources/BrokenSource/Recoverable.swift")
    let validSource = try String(contentsOfFile: sourcePath, encoding: .utf8)
    defer { try? validSource.write(toFile: sourcePath, atomically: true, encoding: .utf8) }

    let workDirectory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(atPath: workDirectory) }

    let runner = SwiftPMBuildRunner(
      repoPath: fixtureRepoPath,
      configuration: .debug,
      scratchPath: (workDirectory as NSString).appendingPathComponent("scratch")
    )
    let buildResult = try runner.produceIndexStore()

    // Corrupt AFTER the build: the index store keeps the anchors from the valid compile while
    // the refiner parses the now-unparseable content — the stale-index case RANGE-03 guards.
    // (swift build fails hard on any syntax error, even inside inactive #if branches, so a
    // committed broken file can never produce occurrences to refine.)
    try Self.corruptedSource.write(toFile: sourcePath, atomically: true, encoding: .utf8)

    let builder = SCIPIndexBuilder(
      repoPath: fixtureRepoPath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: (workDirectory as NSString).appendingPathComponent("index-db"),
      buildToolName: BuildTool.swiftpm.rawValue,
      converterVersion: "test"
    )
    let index = try builder.build()

    let document = try #require(
      index.documents.first { $0.relativePath == "Sources/BrokenSource/Recoverable.swift" }
    )
    #expect(!document.occurrences.isEmpty)

    // Parser.parse never throws: the corrupted file still yields a token map, and line 0 is
    // byte-identical, so its anchors hit `.present` tokens and keep exact ends.
    let getterValueEnds = document.occurrences
      .filter { $0.symbol.contains("5valueSivg") }
      .map(\.singleLineRange)
    #expect(!getterValueEnds.isEmpty, "corrupted file must still emit getter:value occurrences")
    #expect(
      getterValueEnds.contains { $0.line == 0 && $0.startCharacter == 4 && $0.endCharacter == 9 },
      "getter:value must keep the exact token extent [4,9) on the untouched valid region"
    )
    #expect(
      !getterValueEnds.contains { $0.line == 0 && $0.startCharacter == 4 && $0.endCharacter == 16 },
      "getter:value must not fall back to the approximate end 16 (anchor hit the token map)"
    )

    // tailValue's anchor rides on the stale index (line 6 from the valid compile) but the
    // corrupted content only has 6 lines and none starts a token at that anchor, so the lookup
    // misses and the occurrence carries the name-length approximate end:
    // 4 + "getter:tailValue".utf8.count == 20.
    let getterTailValueEnds = document.occurrences
      .filter { $0.symbol.contains("9tailValueSivg") }
      .map(\.singleLineRange)
    #expect(!getterTailValueEnds.isEmpty, "corrupted file must still emit getter:tailValue occurrences")
    #expect(
      getterTailValueEnds.contains { $0.line == 8 && $0.startCharacter == 4 && $0.endCharacter == 20 },
      "getter:tailValue must carry the approximate end [8, 4..20) — its anchor missed the token map"
    )
  }

  @Test("DocumentationFixture end-to-end: docs, exclusions, accessor inheritance, one parse per file, cache pair")
  func documentationFixtureEndToEnd() throws {
    let fixtureRepoPath = Self.documentationFixtureRepoPath()
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
    let databasePath = (workDirectory as NSString).appendingPathComponent("index-db")

    let builder = SCIPIndexBuilder(
      repoPath: fixtureRepoPath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: databasePath,
      buildToolName: BuildTool.swiftpm.rawValue,
      converterVersion: "test"
    )
    let index = try builder.build()

    #expect(index.documents.count == 1)
    let document = try #require(
      index.documents.first { $0.relativePath == "Sources/DocumentationFixture/Documented.swift" }
    )

    func expectDoc(_ fragment: String, _ expected: String, _ what: String) throws {
      let symbol = try #require(
        document.symbols.first { $0.symbol.contains(fragment) },
        "\(what) must appear in the document's symbols"
      )
      #expect(
        symbol.documentation == [expected],
        "\(what) must carry exactly its normalized doc — got \(symbol.documentation)"
      )
    }

    try expectDoc("3addyS2i_SitF", "Adds two integers.", "documented func add")
    try expectDoc(
      "7computeyS2iF",
      "Computes with an attribute between the doc and the declaration.",
      "attributed func compute (doc keyed at the name token past the attribute)"
    )
    try expectDoc(
      "6blocky5valueS2i_tF`.",
      "Block doc first.\n- parameter value: an int\n\nBlock second paragraph.",
      "block-documented func blocky"
    )
    try expectDoc(
      "5noisySiyF",
      "Documented with noise interleaved.",
      "func noisy with a plain comment between doc and decl"
    )
    try expectDoc("10DocumentedC`.", "A documented container.", "class Documented")
    try expectDoc("6storedSivp", "A stored value with accessors.", "var stored definition")
    try expectDoc("6frozenSivg", "Frozen constant.", "let frozen getter")
    try expectDoc("ACycfc", "Makes a documented thing.", "init")
    try expectDoc("5Wholea", "Documented container alias.", "typealias Whole")
    try expectDoc("8SpectrumO`.", "Color spectrum.", "enum Spectrum")
    try expectDoc("8SpectrumO3redy", "Warm hue.", "enum case red")
    try expectDoc("8SpectrumO4bluey", "Cool hue.", "enum case blue")
    try expectDoc("6helperSiyF", "Extension helper.", "extension member helper")

    let subtract = try #require(
      document.symbols.first { $0.symbol.contains("8subtractyS2i_SitF") }
    )
    #expect(subtract.documentation.isEmpty, "undocumented func must keep documentation empty")

    // Accessor inheritance (research D3): synthesized accessor definitions share the property's
    // name-token anchor and inherit its doc — no accessor special-casing anywhere. Explicit
    // accessor bodies anchor at their own get/set keywords and are deliberately not covered.
    let frozenGetter = try #require(document.symbols.first { $0.symbol.contains("6frozenSivg") })
    #expect(
      frozenGetter.documentation == ["Frozen constant."],
      "getter:frozen must inherit the property doc"
    )
    let frozenSetter = try #require(document.symbols.first { $0.symbol.contains("6frozenSivs") })
    #expect(
      frozenSetter.documentation == ["Frozen constant."],
      "setter:frozen must inherit the property doc"
    )

    // DOCS-02 end-to-end: every excluded comment class embeds DOCSMARKER and no documentation
    // field anywhere in the index contains it.
    for doc in index.documents {
      for symbol in doc.symbols {
        #expect(
          !symbol.documentation.contains { $0.contains("DOCSMARKER") },
          "excluded comment leaked into documentation of \(symbol.symbol)"
        )
      }
    }
    for external in index.externalSymbols {
      #expect(
        !external.documentation.contains { $0.contains("DOCSMARKER") },
        "excluded comment leaked into external symbol documentation"
      )
    }

    // DOCS-03 end-to-end: exactly one parse per document's absolute source path.
    for doc in index.documents {
      let absolutePath = (fixtureRepoPath as NSString).appendingPathComponent(doc.relativePath)
      #expect(
        SwiftSyntaxRefiner.parseCount(forFilePath: absolutePath) == 1,
        "\(doc.relativePath) must be parsed exactly once by the fresh run"
      )
    }

    // Cache run-pair (research D5b): a second builder over the same build through one
    // CacheStore serves byte-identical output, identical documentation, and no new parses.
    let cacheDir = (workDirectory as NSString).appendingPathComponent("cache")
    let store = CacheStore(cacheDir: cacheDir)

    let cacheBuilder1 = SCIPIndexBuilder(
      repoPath: fixtureRepoPath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: databasePath,
      buildToolName: BuildTool.swiftpm.rawValue,
      converterVersion: "test",
      cacheStore: store
    )
    let cacheIndex1 = try cacheBuilder1.build()
    let cacheData1 = try cacheIndex1.serializedData()

    var countsAfterCacheRun1: [String: Int] = [:]
    for doc in cacheIndex1.documents {
      let absolutePath = (fixtureRepoPath as NSString).appendingPathComponent(doc.relativePath)
      countsAfterCacheRun1[absolutePath] = SwiftSyntaxRefiner.parseCount(forFilePath: absolutePath)
    }

    let cacheBuilder2 = SCIPIndexBuilder(
      repoPath: fixtureRepoPath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: databasePath,
      buildToolName: BuildTool.swiftpm.rawValue,
      converterVersion: "test",
      cacheStore: store
    )
    let cacheIndex2 = try cacheBuilder2.build()
    let cacheData2 = try cacheIndex2.serializedData()

    #expect(cacheData1 == cacheData2, "cache-hit second run must be byte-identical")
    for doc in cacheIndex2.documents {
      let absolutePath = (fixtureRepoPath as NSString).appendingPathComponent(doc.relativePath)
      #expect(
        SwiftSyntaxRefiner.parseCount(forFilePath: absolutePath)
          == countsAfterCacheRun1[absolutePath],
        "cache hit must add zero parses for \(doc.relativePath)"
      )
    }

    let cacheDocument2 = try #require(
      cacheIndex2.documents.first {
        $0.relativePath == "Sources/DocumentationFixture/Documented.swift"
      }
    )
    let cachedAdd = try #require(
      cacheDocument2.symbols.first { $0.symbol.contains("3addyS2i_SitF") }
    )
    #expect(
      cachedAdd.documentation == ["Adds two integers."],
      "cached run must serve documentation identical to the fresh run"
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

  private static func brokenSourceFixtureRepoPath() -> String {
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return repoRoot.appendingPathComponent("Fixtures/BrokenSourceFixture").path
  }

  static func documentationFixtureRepoPath() -> String {
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return repoRoot.appendingPathComponent("Fixtures/DocumentationFixture").path
  }

  private static let corruptedSource = """
    let value = 21
    func readValue() -> Int { value }
    struct Recoverable { let ok = 1 }

    struct { let x: = }
    let tailValue = 9
    """

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
