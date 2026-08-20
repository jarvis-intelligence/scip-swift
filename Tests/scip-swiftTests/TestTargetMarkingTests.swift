import Foundation
import Testing

@testable import scip_swift

/// Requirement: NAV-03 / D-18 (03-03) — the test-target marking oracle.
///
/// Occurrences in test-target documents carry the Test bit (composed with
/// Definition/Read/Write/Import bits); NO occurrence in library-target documents
/// (Sources/**) carries it. This suite proves BOTH directions over the built
/// SchemeFixture index.
///
/// Detection mechanism (chosen per 03-03 Task 4 / Open Question 3): PRIMARY =
/// PackageTargetMap path/target detection — a document whose relativePath falls under
/// a Package.swift `.testTarget`'s path; SECONDARY = the document's store
/// `location.moduleName` names a test target. The store's `SymbolProperty.unitTest`
/// path in `SymbolRoleMapping` is empirically dead for SwiftPM + Swift Testing targets
/// (03-RESEARCH Q4) and stays as a belt — proven untouched by the existing
/// `SymbolRoleMappingTests` unit-test row.
///
/// Composition decision (RED time): document-level marking includes import
/// occurrences — `@testable import SchemeFixture` emits `import|test` (0x22), pinned
/// below. Imports are facts OF the test document, so the both-direction sweep needs no
/// carve-outs.
@Suite("TestTargetMarking")
struct TestTargetMarkingTests {
  private static let testBit = Int32(Scip_SymbolRole.test.rawValue)
  private static let libraryPrefix = "scip-swift swiftpm SchemeFixture . "
  private static let testDocPath = "Tests/SchemeFixtureTests/SchemeFixtureTests.swift"
  private static let sourcesDocPaths = [
    "Sources/SchemeFixture/SchemeFixture.swift",
    "Sources/SchemeFixtureExt/SchemeFixtureExt.swift",
  ]

  // MARK: - Test 1: both directions

  @Test("every occurrence in the test-target document carries the Test bit (definitions and references)")
  func testDocumentOccurrencesAllCarryTestBit() throws {
    let index = try Self.sharedIndex()

    let testOccurrences = index.documents[Self.testDocPath] ?? []
    #expect(!testOccurrences.isEmpty, "the test-target document must have occurrences")

    let unmarked = testOccurrences.filter { $0.symbolRoles & Self.testBit == 0 }
    let unmarkedPreview = unmarked.prefix(5).map { "(\($0.symbol), roles \($0.symbolRoles))" }
    #expect(
      unmarked.isEmpty,
      "every test-target occurrence must carry the Test bit (locate-tests-for-a-symbol query); unmarked: \(unmarkedPreview)")

    // The references to SchemeFixture/SchemeFixtureExt symbols are marked too — that is
    // the query "which tests reference X".
    let libraryRefs = testOccurrences.filter {
      $0.symbol.hasPrefix(Self.libraryPrefix) || $0.symbol.hasPrefix("scip-swift swiftpm SchemeFixtureExt . ")
    }
    #expect(!libraryRefs.isEmpty, "the test document must reference library symbols")
    #expect(libraryRefs.allSatisfy { $0.symbolRoles & Self.testBit != 0 })
  }

  @Test("no occurrence in any Sources/** library document carries the Test bit")
  func libraryDocumentOccurrencesCarryNoTestBit() throws {
    let index = try Self.sharedIndex()

    for docPath in Self.sourcesDocPaths {
      let occurrences = index.documents[docPath] ?? []
      #expect(!occurrences.isEmpty, "\(docPath) must have occurrences")
      let marked = occurrences.filter { $0.symbolRoles & Self.testBit != 0 }
      let markedPreview = marked.prefix(5).map { "(\($0.symbol), roles \($0.symbolRoles))" }
      #expect(
        marked.isEmpty,
        "library documents must never carry the Test bit; marked: \(markedPreview)")
    }
  }

  // MARK: - Test 2: composed bit values on pinned sites

  @Test("Test composes with Definition/Write/Read/Import on pinned sites")
  func composedTestBitValues() throws {
    let index = try Self.sharedIndex()
    let test = try Self.testsFixture()

    // definition|test (0x21) on the test suite struct's own definition. The struct's
    // USR is a local-context mangling the parser does not decode, so its definition
    // renders as the D-06 fallback Term anchored at the @Suite attribute line (the
    // store's anchor for the declaration) — pinned exactly, hash-free and deterministic.
    let suiteLine = try Self.uniqueLine(in: test, containing: "@Suite(")
    let structDefs = index.occurrences(in: Self.testDocPath, atLine: suiteLine)
      .filter { $0.symbol == "scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV`." }
    #expect(!structDefs.isEmpty, "the suite struct definition must be present")
    for occurrence in structDefs {
      #expect(
        occurrence.symbolRoles == 0x21,
        "definition|test expected (got \(occurrence.symbolRoles) on \(occurrence.symbol))")
    }

    // write|test (0x24) on the Poster.label property write.
    let writeLine = try Self.uniqueLine(in: test, containing: #"poster.label = "demo""#)
    let writes = index.occurrences(in: Self.testDocPath, atLine: writeLine)
      .filter { $0.symbol == Self.libraryPrefix + "Poster#label." }
    #expect(!writes.isEmpty, "the Poster#label write must be present")
    for occurrence in writes {
      #expect(
        occurrence.symbolRoles == 0x24,
        "write|test expected (got \(occurrence.symbolRoles) on \(occurrence.symbol))")
    }

    // read|test (0x28) on the Vec initializer reference in `let vector = Vec(x: 1, y: 2)`.
    let readLine = try Self.uniqueLine(in: test, containing: "let vector = Vec(x: 1, y: 2)")
    let reads = index.occurrences(in: Self.testDocPath, atLine: readLine)
      .filter { $0.symbol.hasPrefix(Self.libraryPrefix + "Vec#init") }
    #expect(!reads.isEmpty, "the Vec init reference must be present")
    for occurrence in reads {
      #expect(
        occurrence.symbolRoles == 0x28,
        "read|test expected (got \(occurrence.symbolRoles) on \(occurrence.symbol))")
    }

    // import|test (0x22) on `@testable import SchemeFixture` — document-level marking
    // includes imports (composition decision at RED time, pinned here).
    let importLine = try Self.uniqueLine(
      in: test, trimmedEquals: "@testable import SchemeFixture")
    let imports = index.occurrences(in: Self.testDocPath, atLine: importLine)
      .filter { $0.symbol == "scip-swift swiftpm SchemeFixture . SchemeFixture/" }
    #expect(!imports.isEmpty, "the @testable import occurrence must be present")
    for occurrence in imports {
      #expect(
        occurrence.symbolRoles == 0x22,
        "import|test expected (got \(occurrence.symbolRoles) on \(occurrence.symbol))")
    }
  }

  // MARK: - Built-index plumbing (same shape as ImportOccurrenceTests)

  private struct BuiltIndex {
    let documents: [String: [Scip_Occurrence]]

    init(_ index: Scip_Index) {
      var documents: [String: [Scip_Occurrence]] = [:]
      for document in index.documents {
        documents[document.relativePath] = document.occurrences
      }
      self.documents = documents
    }

    func occurrences(in relativePath: String, atLine line: Int32) -> [Scip_Occurrence] {
      (documents[relativePath] ?? []).filter { $0.singleLineRange.line == line }
    }
  }

  private static let indexBox = IndexBox()

  private static func sharedIndex() throws -> BuiltIndex {
    try indexBox.get()
  }

  private final class IndexBox: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: BuiltIndex?

    func get() throws -> BuiltIndex {
      lock.lock()
      defer { lock.unlock() }
      if let cached { return cached }
      let built = BuiltIndex(try TestTargetMarkingTests.buildFixtureIndex())
      cached = built
      return built
    }
  }

  /// Mirrors `ScipCLIGateTests.buildIndex` (private there): SwiftPMBuildRunner produces
  /// the index store, `swift build --build-tests` folds the test target into the same
  /// store, then the in-process SCIPIndexBuilder emits the Scip_Index.
  private static func buildFixtureIndex() throws -> Scip_Index {
    let fixtureRepoPath = Self.fixtureRepoPath()
    let fixtureBuildPath = (fixtureRepoPath as NSString).appendingPathComponent(".build")
    defer { try? FileManager.default.removeItem(atPath: fixtureBuildPath) }

    let workDirectory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(atPath: workDirectory) }
    let scratchPath = (workDirectory as NSString).appendingPathComponent("scratch")

    let runner = SwiftPMBuildRunner(
      repoPath: fixtureRepoPath, configuration: .debug, scratchPath: scratchPath)
    let buildResult = try runner.produceIndexStore()

    let swift = try SubprocessRunner.resolveExecutable(named: "swift")
    let buildTests = try SubprocessRunner.run(
      executable: swift,
      arguments: ["build", "--configuration", "debug", "--scratch-path", scratchPath,
                  "--enable-index-store", "--build-tests"],
      currentDirectory: fixtureRepoPath
    )
    guard buildTests.exitCode == 0 else {
      throw BuildError.buildFailed(
        tool: "swift build --build-tests", exitCode: buildTests.exitCode,
        output: buildTests.combinedOutput)
    }

    let builder = SCIPIndexBuilder(
      repoPath: fixtureRepoPath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: (workDirectory as NSString).appendingPathComponent("index-db"),
      buildToolName: BuildTool.swiftpm.rawValue,
      converterVersion: "test"
    )
    return try builder.build()
  }

  private static func fixtureRepoPath() -> String {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/SchemeFixture").path
  }

  private static func makeTemporaryDirectory() throws -> String {
    let path = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("scip-swift-test-marking-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }

  private struct Fixture {
    let relativePath: String
    let lines: [String]
  }

  private static func testsFixture() throws -> Fixture {
    let path = (Self.fixtureRepoPath() as NSString).appendingPathComponent(Self.testDocPath)
    let text = try String(contentsOfFile: path, encoding: .utf8)
    return Fixture(relativePath: Self.testDocPath, lines: text.components(separatedBy: "\n"))
  }

  private static func uniqueLine(in fixture: Fixture, containing anchor: String) throws -> Int32 {
    let matches = fixture.lines.enumerated().filter { $0.element.contains(anchor) }
    guard matches.count == 1, let index = matches.first?.offset else {
      throw TestMarkingAnchorError(anchor: anchor, file: fixture.relativePath)
    }
    return Int32(index)
  }

  private static func uniqueLine(in fixture: Fixture, trimmedEquals needle: String) throws -> Int32 {
    let matches = fixture.lines.enumerated().filter {
      $0.element.trimmingCharacters(in: .whitespaces) == needle
    }
    guard matches.count == 1, let index = matches.first?.offset else {
      throw TestMarkingAnchorError(anchor: needle, file: fixture.relativePath)
    }
    return Int32(index)
  }

  private struct TestMarkingAnchorError: Error, CustomStringConvertible {
    let anchor: String
    let file: String
    var description: String {
      "fixture anchor '\(anchor)' in \(file) must match exactly one line"
    }
  }
}
