import Foundation
import Testing

@testable import scip_swift

/// Requirement: SYM-04 / D-17 (03-03) — the import-occurrence oracle.
///
/// Every written `import` / `@testable import` statement must emit EXACTLY ONE
/// occurrence with the Import symbol role (0x2) resolving to the module's canonical
/// symbol, REPLACING the old reference-with-fallback-Term line at the same anchor
/// (never duplicating it — the (symbol, range, roles) dedup key must not end up
/// holding two occurrences per import).
///
/// Module symbol forms (the frozen Phase-1 scheme, correcting D-17's literal — module
/// descriptors end in `/`, never `#`):
/// - repo-local target module:  `scip-swift swiftpm <Module> . <Module>/`
/// - external/system module:    `scip-swift swift <Module> <pin> <Module>/`
/// The manager choice comes from PackageTargetMap membership: a module named in the
/// repo's Package.swift targets uses `swiftpm`; everything else uses `swift` plus the
/// pinned toolchain version. Implicit/macro module occurrences (Swift Testing's
/// `c:@M@Testing` flood at #expect/@Suite sites) must NEVER carry the Import role.
@Suite("ImportOccurrence")
struct ImportOccurrenceTests {


  // MARK: - Task 2 (tracer): one import end-to-end

  @Test("tracer: import SchemeFixture emits exactly one Import-role occurrence on the module symbol")
  func tracerImportSchemeFixture() throws {
    let index = try Self.sharedIndex()
    let ext = try Self.extensionFixture()

    let line = try Self.uniqueLine(in: ext, containing: "import SchemeFixture")
    let anchor = try Self.moduleNameAnchor(line: Int(line), in: ext, module: "SchemeFixture")

    let lineOccurrences = index.occurrences(in: ext.relativePath, atLine: line)
    let observed = lineOccurrences.map { "(\($0.symbol), roles \($0.symbolRoles))" }
    #expect(
      lineOccurrences.count == 1,
      "the import anchor must carry exactly one occurrence (replacement, not duplication): \(observed)")

    let occurrence = try #require(lineOccurrences.first)
    #expect(occurrence.symbol == "scip-swift swiftpm SchemeFixture . SchemeFixture/")
    #expect(
      occurrence.symbolRoles == Int32(Scip_SymbolRole.import.rawValue),
      "roles must be exactly Import (2), got \(occurrence.symbolRoles)")
    #expect(occurrence.singleLineRange.startCharacter == anchor.start)
    #expect(occurrence.singleLineRange.endCharacter == anchor.end)
  }

  @Test("tracer: the module symbol is registered in externalSymbols with the module name")
  func tracerModuleSymbolRegisteredExternally() throws {
    let index = try Self.sharedIndex()

    let moduleSymbol = "scip-swift swiftpm SchemeFixture . SchemeFixture/"
    let registered = index.externalSymbols.first { $0.symbol == moduleSymbol }
    #expect(registered != nil, "module symbol must be registered for lint (missingSymbolForOccurrenceError)")
    #expect(registered?.displayName == "SchemeFixture")
  }

  // MARK: - Built-index plumbing (mirrors RoleParityTests / ScipCLIGateTests.buildIndex)

  private struct FlatOccurrence: Hashable {
    let relativePath: String
    let line: Int32
    let startCharacter: Int32
    let symbol: String
    let symbolRoles: Int32

    init(relativePath: String, occurrence: Scip_Occurrence) {
      self.relativePath = relativePath
      self.line = occurrence.singleLineRange.line
      self.startCharacter = occurrence.singleLineRange.startCharacter
      self.symbol = occurrence.symbol
      self.symbolRoles = occurrence.symbolRoles
    }
  }

  private struct BuiltIndex {
    let documents: [String: [Scip_Occurrence]]
    let allOccurrences: [FlatOccurrence]
    let externalSymbols: [Scip_SymbolInformation]

    init(_ index: Scip_Index) {
      var documents: [String: [Scip_Occurrence]] = [:]
      var flat: [FlatOccurrence] = []
      for document in index.documents {
        documents[document.relativePath] = document.occurrences
        for occurrence in document.occurrences {
          flat.append(FlatOccurrence(relativePath: document.relativePath, occurrence: occurrence))
        }
      }
      self.documents = documents
      self.allOccurrences = flat
      self.externalSymbols = index.externalSymbols
    }

    func occurrences(in relativePath: String, atLine line: Int32) -> [Scip_Occurrence] {
      (documents[relativePath] ?? []).filter { $0.singleLineRange.line == line }
    }
  }

  /// One cached fixture build per test run — every test here asserts over the same
  /// corpus (a real `swift build --build-tests`); one build is enough.
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
      let built = BuiltIndex(try ImportOccurrenceTests.buildFixtureIndex())
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
      .appendingPathComponent("scip-swift-import-occ-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }

  // MARK: - Fixture sources (structural line resolution — the source is the truth)

  private struct Fixture {
    let relativePath: String
    let lines: [String]
  }

  private static func extensionFixture() throws -> Fixture {
    try fixture("Sources/SchemeFixtureExt/SchemeFixtureExt.swift")
  }

  private static func fixture(_ relativePath: String) throws -> Fixture {
    let path = (Self.fixtureRepoPath() as NSString).appendingPathComponent(relativePath)
    let text = try String(contentsOfFile: path, encoding: .utf8)
    return Fixture(relativePath: relativePath, lines: text.components(separatedBy: "\n"))
  }

  /// The unique 0-based line in `fixture` whose text contains `anchor` (0-based, like
  /// the emitted `singleLineRange.line`).
  private static func uniqueLine(in fixture: Fixture, containing anchor: String) throws -> Int32 {
    let matches = fixture.lines.enumerated().filter { $0.element.contains(anchor) }
    guard matches.count == 1, let index = matches.first?.offset else {
      throw ImportAnchorError(
        anchor: anchor, file: fixture.relativePath, matchedLines: matches.map(\.offset))
    }
    return Int32(index)
  }

  /// The 0-based utf8 column range of the module-name token on an import line — the
  /// LAST occurrence of the module name in the line, so `@testable import X` anchors
  /// past the attribute exactly as the store does (utf8 col 18 for `@testable import X`).
  private static func moduleNameAnchor(
    line: Int, in fixture: Fixture, module: String
  ) throws -> (start: Int32, end: Int32) {
    let text = fixture.lines[line]
    guard let range = text.range(of: module, options: .backwards) else {
      throw ImportAnchorError(
        anchor: module, file: fixture.relativePath, matchedLines: [line])
    }
    let start = text.utf8.distance(from: text.utf8.startIndex, to: range.lowerBound.samePosition(in: text.utf8)!)
    return (Int32(start), Int32(start + module.utf8.count))
  }

  private struct ImportAnchorError: Error, CustomStringConvertible {
    let anchor: String
    let file: String
    let matchedLines: [Int]
    var description: String {
      "fixture anchor '\(anchor)' in \(file) must match exactly one line, matched lines "
        + "\(matchedLines)"
    }
  }
}
