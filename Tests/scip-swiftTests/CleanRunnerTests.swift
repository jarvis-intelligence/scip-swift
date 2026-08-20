import Foundation
import Testing

@testable import scip_swift

/// Requirement: PROJ-01 / D-20 (03-03) — the clean-runner reproducibility gate.
///
/// PROJ-01's "cold cache, same results" needs a WIRED gate, not a manual claim:
/// - two cold runs with a persistent `--cache-dir` (the dir DELETED between runs)
///   produce byte-identical serializedData() with non-empty documents/symbols/
///   occurrences and definition/reference counts above thresholds — never an
///   empty-but-lint-clean index;
/// - the CLI-default path (no cache dir) is cold by construction — two runs must also
///   be byte-identical;
/// - a build failure surfaces as an actionable error: `BuildError.buildFailed` whose
///   message names the build tool and carries the compiler output;
/// - a cache written under symbol format 3 is wholesale-invalidated by the next run
///   (the manifest gate D-09 rides when the format version bumps).
@Suite("CleanRunner")
struct CleanRunnerTests {
  private static let definitionBit = Int32(Scip_SymbolRole.definition.rawValue)
  private static let referenceBits =
    Int32(Scip_SymbolRole.readAccess.rawValue) | Int32(Scip_SymbolRole.writeAccess.rawValue)
    | Int32(Scip_SymbolRole.import.rawValue)

  // MARK: - Test 1: wiped persistent cache, cold double-run

  @Test("wiped persistent cache: two cold runs are byte-identical and non-empty")
  func wipedPersistentCacheDoubleRunIsByteIdentical() throws {
    let fixtureRepoPath = try Self.materializeFixtureCopy("SchemeFixture")
    defer { try? FileManager.default.removeItem(atPath: fixtureRepoPath) }

    let workDirectory = try Self.makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: workDirectory) }
    let cacheDir = (workDirectory as NSString).appendingPathComponent("cache")

    let first = try Self.index(fixtureRepoPath: fixtureRepoPath, cacheDir: cacheDir)

    // The wipe: a cold run means the cache dir does not exist when the run starts.
    try FileManager.default.removeItem(atPath: cacheDir)
    let second = try Self.index(fixtureRepoPath: fixtureRepoPath, cacheDir: cacheDir)

    try Self.assertReproducibleAndSubstantive(first, second, threshold: 20)
  }

  // MARK: - Test 2: CLI-default cold path

  @Test("CLI-default path (temp-dir cold by construction): two runs byte-identical")
  func cliDefaultColdPathDoubleRunIsByteIdentical() throws {
    let fixtureRepoPath = try Self.materializeFixtureCopy("SchemeFixture")
    defer { try? FileManager.default.removeItem(atPath: fixtureRepoPath) }

    let first = try Self.index(fixtureRepoPath: fixtureRepoPath, cacheDir: nil)
    let second = try Self.index(fixtureRepoPath: fixtureRepoPath, cacheDir: nil)

    try Self.assertReproducibleAndSubstantive(first, second, threshold: 20)
  }

  // MARK: - Test 3: actionable build failure

  @Test("injected syntax error fails as BuildError.buildFailed naming the tool and carrying output")
  func syntaxErrorFailsActionably() throws {
    // A COPY of the fixture is corrupted BEFORE building — committed fixtures must
    // stay buildable (IntegrationTests precedent: swift build fails hard on syntax
    // errors, so the corruption can only ever live in a temp copy).
    let fixtureRepoPath = try Self.materializeFixtureCopy("MiniSwiftPackage")
    defer { try? FileManager.default.removeItem(atPath: fixtureRepoPath) }
    let sourcePath = (fixtureRepoPath as NSString)
      .appendingPathComponent("Sources/MiniSwiftPackage/Greeter.swift")
    var source = try String(contentsOfFile: sourcePath, encoding: .utf8)
    source += "\nfunc injectedSyntaxErrorMarker( {\n"
    try source.write(toFile: sourcePath, atomically: true, encoding: .utf8)

    do {
      _ = try Self.index(fixtureRepoPath: fixtureRepoPath, cacheDir: nil)
      Issue.record("a syntax error must throw BuildError.buildFailed, never emit an index")
      return
    } catch let error as BuildError {
      guard case .buildFailed(let tool, let exitCode, let output) = error else {
        Issue.record("expected .buildFailed, got \(error)")
        return
      }
      #expect(exitCode != 0)
      #expect(tool == "swift build", "the message must name the build tool")
      let message = String(describing: error)
      #expect(message.contains("swift build"), "tool name rides in the message")
      #expect(
        output.contains("error:"), "compiler output must be carried in full: \(output.prefix(200))")
      #expect(
        output.contains("injectedSyntaxErrorMarker"),
        "the failing source line must appear in the compiler output")
    }
  }

  // MARK: - Test 4: format-gate regression (D-09)

  @Test("a format-3 cache is wholesale-invalidated by the next run (manifest gate)")
  func formatThreeCacheWholesaleInvalidates() throws {
    let fixtureRepoPath = try Self.materializeFixtureCopy("SchemeFixture")
    defer { try? FileManager.default.removeItem(atPath: fixtureRepoPath) }

    let workDirectory = try Self.makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: workDirectory) }
    let cacheDir = (workDirectory as NSString).appendingPathComponent("cache")

    let first = try Self.index(fixtureRepoPath: fixtureRepoPath, cacheDir: cacheDir)

    // Rewind the written manifest to format 3 — the pre-03-03 format. Everything else
    // stays identical so symbolFormatVersion is the ONLY invalidation trigger.
    let store = CacheStore(cacheDir: cacheDir)
    let manifest = try #require(store.loadManifest(), "run 1 must have written a manifest")
    #expect(manifest.symbolFormatVersion == SymbolFormatVersion.current)
    var stale = manifest
    stale.symbolFormatVersion = 3
    try store.saveManifest(stale)

    let second = try Self.index(fixtureRepoPath: fixtureRepoPath, cacheDir: cacheDir)

    // The gate rewrote the manifest at the current format, and the rebuilt output is
    // byte-identical to the fresh run.
    let rewritten = try #require(store.loadManifest(), "run 2 must have rewritten the manifest")
    #expect(
      rewritten.symbolFormatVersion == SymbolFormatVersion.current,
      "a stale-format manifest must be replaced wholesale (got \(rewritten.symbolFormatVersion))")
    try Self.assertReproducibleAndSubstantive(first, second, threshold: 20)
  }

  // MARK: - Plumbing

  /// Runs the real pipeline (`IndexCommand.indexOneRepo`) over a fixture copy.
  private static func index(fixtureRepoPath: String, cacheDir: String?) throws -> Scip_Index {
    try IndexCommand.indexOneRepo(
      repoPath: fixtureRepoPath,
      output: nil,
      buildTool: nil,
      configuration: .debug,
      scheme: nil,
      cacheDir: cacheDir,
      indexOnly: false,
      symbolVersion: "",
      demangle: true
    )
  }

  /// The PROJ-01 non-emptiness + threshold contract over two runs' bytes.
  private static func assertReproducibleAndSubstantive(
    _ first: Scip_Index, _ second: Scip_Index, threshold: Int
  ) throws {
    let firstData = try first.serializedData()
    let secondData = try second.serializedData()
    #expect(firstData == secondData, "cold double-runs must be byte-identical")

    // Never an empty-but-lint-clean index: documents, per-document symbols AND
    // occurrences, and role-bearing counts above the fixture-scaled threshold.
    #expect(!second.documents.isEmpty, "documents must be non-empty")
    var definitions = 0
    var references = 0
    for document in second.documents {
      #expect(!document.symbols.isEmpty, "\(document.relativePath) must emit symbols")
      #expect(!document.occurrences.isEmpty, "\(document.relativePath) must emit occurrences")
      for occurrence in document.occurrences {
        if occurrence.symbolRoles & definitionBit != 0 { definitions += 1 }
        if occurrence.symbolRoles & referenceBits != 0 { references += 1 }
      }
    }
    #expect(definitions > threshold, "definition count \(definitions) must exceed \(threshold)")
    #expect(references > threshold, "reference-bearing count \(references) must exceed \(threshold)")
  }

  private static func materializeFixtureCopy(_ fixtureName: String) throws -> String {
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let source = repoRoot.appendingPathComponent("Fixtures/\(fixtureName)").path
    let copy = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("scip-swift-clean-runner-\(fixtureName)-\(UUID().uuidString)")
    try FileManager.default.copyItem(atPath: source, toPath: copy)
    return copy
  }

  private static func makeTempDir() throws -> String {
    let path = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("scip-swift-clean-runner-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }
}
