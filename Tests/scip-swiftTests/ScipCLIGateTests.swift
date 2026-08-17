import Foundation
import Testing

@testable import scip_swift

/// Requirement: SYM-03 verification half / FBQ-02 fixture portion / D-13 (02-03 Task 1) — gate
/// emitted indexes with the real `scip` CLI from the orchestrator repo (scip-code/scip).
///
/// `scip lint` must exit 0 with zero `error:`-prefixed findings on every fixture index the
/// engine emits. The binary is located via `SCIP_BIN` (CI pins a checksum-verified release
/// download, D-12) or PATH (local dev: `~/.local/bin/scip`); when neither provides a binary
/// the tests FAIL with actionable guidance — the gate never passes vacuously and never
/// silently skips (plan prohibition). Subprocess invocation uses fixed argument vectors over
/// single-argument paths — no shell interpolation (T-02-08).
@Suite("ScipCLIGate")
struct ScipCLIGateTests {
  @Test("MiniSwiftPackage index passes scip lint (tracer path)")
  func miniSwiftPackagePassesLint() throws {
    let index = try Self.buildIndex(fixtureName: "MiniSwiftPackage")
    try Self.lintExpectingZeroErrors(index, fixtureName: "MiniSwiftPackage")
  }

  @Test("SchemeFixture index passes scip lint")
  func schemeFixturePassesLint() throws {
    let index = try Self.buildIndex(fixtureName: "SchemeFixture")
    try Self.lintExpectingZeroErrors(index, fixtureName: "SchemeFixture")
  }

  @Test("SchemeFixture covers the full FBQ-02 category list")
  func schemeFixtureCoversCategories() throws {
    let index = try Self.buildIndex(fixtureName: "SchemeFixture")
    let symbols = Set(index.documents.flatMap { $0.symbols.map(\.symbol) })
    let systemVersion = ToolchainInfo.pinnedSwiftVersion

    func expectPresent(_ symbol: String, _ what: String) {
      #expect(symbols.contains(symbol), "\(what) must be emitted — expected \(symbol)")
    }

    let target = "scip-swift swiftpm SchemeFixture . "
    let system = "scip-swift swift Swift \(systemVersion) "

    // Same-file extension member rides the extended type's path (SYM-02).
    expectPresent("\(target)Vec#length().", "same-file extension member")
    // Cross-file (cross-module) extension member: declared in SchemeFixtureExt, emitted under
    // the extended type's OWNING module header, never the extending module.
    expectPresent("\(target)Box#describe().", "cross-file extension member")
    // Retroactive extension on String: the extended type's owner module is Swift (system
    // header), never SchemeFixtureExt (SYM-02, golden row 22 analog).
    expectPresent("\(system)String#schemeShout().", "retroactive extension member")

    // Protocol + conformance witness.
    expectPresent("\(target)Drawable#", "protocol type")
    expectPresent("\(target)Drawable#draw().", "protocol requirement method")
    expectPresent("\(target)Poster#draw().", "conformance witness method")

    // Generic type. (The [T] type-parameter descriptor itself has no IndexStoreDB Symbol.Kind
    // — genericTypeParam is not a store symbol — so its rendering rule stays covered by the
    // SymbolSchemeGolden suite; here the generic shape must at least emit its type + method.)
    expectPresent("\(target)Box#", "generic type")
    expectPresent("\(target)Box#unwrap().", "method of a generic type")

    // Operator declarations: "==" escapes (non-identifier characters), "+" does not.
    expectPresent("\(target)Vec#`==`().", "== operator")
    expectPresent("\(target)Vec#+().", "+ operator")

    // Accessors: getter, setter, and willSet (willSet renders the setter-family `name=` form).
    expectPresent("\(target)Observed#computed().", "getter accessor")
    expectPresent("\(target)Observed#`computed=`().", "setter accessor")
    expectPresent("\(target)Observed#`watched=`().", "willSet accessor")

    // #if-wrapped declaration.
    expectPresent("\(target)conditionallyCompiled().", "#if-wrapped declaration")

    // Overloaded funcs and inits: source order assigns (+N) from the second member on.
    expectPresent("\(target)parse().", "first overloaded func")
    expectPresent("\(target)parse(+1).", "second overloaded func (+N)")
    expectPresent("\(target)Vec#init().", "first overloaded init")
    expectPresent("\(target)Vec#init(+1).", "second overloaded init (+N)")

    // Enum case and typealias round out the Term/Type descriptor families.
    expectPresent("\(target)Spectrum#red.", "enum case")
    expectPresent("\(target)Point#", "typealias")

    // Emoji/CJK identifiers (D-11): non-ASCII names backtick-escape; content below the
    // descriptor is data, never instructions (T-02-09).
    expectPresent("\(target)`🚀`.", "rocket-emoji constant")
    expectPresent("\(target)`π`.", "pi constant")
    expectPresent("\(target)`名前を付ける`().", "CJK function")

    // Test-target category: the fixture builds its test target into the same index store
    // (--build-tests), so the test file must appear as an indexed document.
    let documentPaths = Set(index.documents.map(\.relativePath))
    #expect(
      documentPaths.contains("Tests/SchemeFixtureTests/SchemeFixtureTests.swift"),
      "the SchemeFixtureTests test target must be indexed (built via --build-tests)"
    )
  }

  @Test("missing scip binary fails loudly, never skips")
  func missingBinaryFailsLoudly() throws {
    // Neither SCIP_BIN nor a PATH lookup provides a binary: discovery must throw an
    // actionable error naming both options (plan prohibition against a vacuous gate).
    #expect(throws: ScipBinaryMissingError.self) {
      _ = try ScipCLIGate.locateScipBinary(environment: [:], whichLookup: { _ in nil })
    }
  }

  @Test("scip binary version matches the engine's scip-cli pin")
  func scipBinaryVersionMatchesEnginePin() throws {
    // D-14: the CI workflow pins one SCIP_CLI_VERSION and downloads that exact release; the
    // engine records the same version in ScipSwiftVersion.scipCliVersion. Drift between the
    // binary actually gating and the engine constant fails here. Local dev binaries carry a
    // `-dev` suffix (v0.9.0-dev), so the BASE version is compared — CI's checksum-verified
    // release binary reports the bare pinned version.
    let scip = try ScipCLIGate.locateScipBinary()
    let result = try SubprocessRunner.run(
      executable: scip,
      arguments: ["--version"],
      currentDirectory: "/"
    )
    #expect(result.exitCode == 0, "scip --version must exit 0 (it is not the 'version' subcommand)")
    let firstLine = result.combinedOutput.split(separator: "\n").first.map(String.init) ?? ""
    #expect(
      firstLine.hasPrefix("scip version v"),
      "expected a leading 'scip version vX.Y.Z' line, got: \(firstLine)"
    )
    let reported = firstLine
      .dropFirst("scip version v".count)
      .split(separator: "-").first.map(String.init) ?? ""
    #expect(
      reported == ScipSwiftVersion.scipCliVersion,
      "gating scip binary base version \(reported) != engine pin \(ScipSwiftVersion.scipCliVersion)"
    )
  }

  @Test("ToolInfo carries the stable scip-cli version entry")
  func toolInfoCarriesStableScipCliVersionEntry() throws {
    // D-14: the pin is visible in ToolInfo as a constant synthetic entry — never argv, so
    // 02-02's argv-insensitive metadata determinism holds (byte-stable across runs).
    let builder = SCIPIndexBuilder(
      repoPath: "/tmp/scip-gate-fixture-repo",
      indexStorePath: "/tmp/nonexistent-index-store",
      databasePath: "/tmp/nonexistent-index-db",
      buildToolName: BuildTool.swiftpm.rawValue,
      converterVersion: "test"
    )
    let entry = "scip-cli-version=\(ScipSwiftVersion.scipCliVersion)"
    let metadata1 = builder.makeMetadata()
    #expect(metadata1.toolInfo.arguments.contains(entry), "ToolInfo must carry \(entry)")

    let index = try Self.buildIndex(fixtureName: "SchemeFixture")
    #expect(
      index.metadata.toolInfo.arguments.contains(entry),
      "a real emitted index must carry the stable scip-cli version entry in ToolInfo"
    )
    #expect(
      index.metadata.toolInfo.arguments == builder.makeMetadata().toolInfo.arguments,
      "the ToolInfo arguments must be the same constant set on every run"
    )
  }

  @Test("SchemeFixture snapshot goldens match scip snapshot output")
  func schemeFixtureSnapshotGoldensMatch() throws {
    // D-13 / A6: `scip snapshot` has no verify mode — the CLI writes caret-annotated files,
    // and this harness owns the directory diff against the committed goldens. Set
    // UPDATE_GOLDENS=1 to regenerate the committed goldens after an intentional emission
    // change (documented in the README).
    let index = try Self.buildIndex(fixtureName: "SchemeFixture")
    let scip = try ScipCLIGate.locateScipBinary()
    let fixtureRepoPath = Self.fixtureRepoPath(fixtureName: "SchemeFixture")

    let workDirectory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(atPath: workDirectory) }
    let indexPath = (workDirectory as NSString).appendingPathComponent("SchemeFixture.scip")
    try index.serializedData().write(to: URL(fileURLWithPath: indexPath))
    let outputDirectory = (workDirectory as NSString).appendingPathComponent("snapshot")

    let result = try SubprocessRunner.run(
      executable: scip,
      arguments: [
        "snapshot", "--from", indexPath, "--to", outputDirectory,
        "--project-root", fixtureRepoPath,
      ],
      currentDirectory: "/"
    )
    #expect(result.exitCode == 0, "scip snapshot must exit 0: \(result.combinedOutput)")

    let goldensDirectory = Self.schemeFixtureGoldensPath()
    if ProcessInfo.processInfo.environment["UPDATE_GOLDENS"] == "1" {
      try FileManager.default.removeItem(atPath: goldensDirectory)
      try FileManager.default.copyItem(atPath: outputDirectory, toPath: goldensDirectory)
      return
    }

    let produced = try Self.filesRecursively(under: outputDirectory)
    let committed = try Self.filesRecursively(under: goldensDirectory)
    #expect(
      !committed.isEmpty,
      "no committed goldens under \(goldensDirectory) — run UPDATE_GOLDENS=1 swift test to create them"
    )

    let producedSet = Set(produced)
    let committedSet = Set(committed)
    if producedSet != committedSet {
      let missing = committedSet.subtracting(producedSet).sorted()
      let extra = producedSet.subtracting(committedSet).sorted()
      Issue.record(
        "golden file sets differ — missing from output: \(missing), unexpected: \(extra). "
          + "Intentional change? Regenerate with UPDATE_GOLDENS=1."
      )
      return
    }

    for relativePath in committedSet.sorted() {
      let producedText = try String(
        contentsOfFile: (outputDirectory as NSString).appendingPathComponent(relativePath),
        encoding: .utf8)
      let committedText = try String(
        contentsOfFile: (goldensDirectory as NSString).appendingPathComponent(relativePath),
        encoding: .utf8)
      if producedText != committedText {
        let diff = Self.firstDiffLines(between: committedText, and: producedText)
        Issue.record(
          "golden drift in \(relativePath) — regenerate with UPDATE_GOLDENS=1 if intentional:\n\(diff)"
        )
      }
    }
  }

  // MARK: - Shared gate plumbing

  /// Errors when the `scip` binary cannot be located. The message names both resolution
  /// options so a human can fix the environment; the gate tests fail on this, never skip.
  struct ScipBinaryMissingError: Error, CustomStringConvertible {
    var description: String {
      "scip CLI not found: set SCIP_BIN to the scip binary path, or install scip "
        + "(https://github.com/scip-code/scip) so it is on PATH"
    }
  }

  enum ScipCLIGate {
    /// Resolves the `scip` binary path: `SCIP_BIN` (must point at an executable file) wins,
    /// else a PATH lookup. Throws `ScipBinaryMissingError` naming both options when neither
    /// resolves — the caller's test then fails loudly.
    static func locateScipBinary(
      environment: [String: String] = ProcessInfo.processInfo.environment,
      whichLookup: (String) -> String? = Self.pathLookup
    ) throws -> String {
      if let configured = environment["SCIP_BIN"] {
        guard FileManager.default.isExecutableFile(atPath: configured) else {
          throw ScipBinaryMissingError()
        }
        return configured
      }
      guard let onPath = whichLookup("scip") else {
        throw ScipBinaryMissingError()
      }
      return onPath
    }

    /// PATH lookup for an executable name via `/usr/bin/env which` (no shell interpolation).
    private static func pathLookup(_ name: String) -> String? {
      guard
        let result = try? SubprocessRunner.run(
          executable: "/usr/bin/env",
          arguments: ["which", name],
          currentDirectory: "/"
        ),
        result.exitCode == 0
      else { return nil }
      let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
      return path.isEmpty ? nil : path
    }
  }

  /// Builds the named fixture's index end-to-end: `swift build --enable-index-store` (plus
  /// `--build-tests` so test targets enter the same store), then the in-process SCIPIndexBuilder.
  private static func buildIndex(fixtureName: String) throws -> Scip_Index {
    let fixtureRepoPath = Self.fixtureRepoPath(fixtureName: fixtureName)
    let fixtureBuildPath = (fixtureRepoPath as NSString).appendingPathComponent(".build")
    defer { try? FileManager.default.removeItem(atPath: fixtureBuildPath) }

    let workDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(atPath: workDirectory) }
    let scratchPath = (workDirectory as NSString).appendingPathComponent("scratch")

    let runner = SwiftPMBuildRunner(
      repoPath: fixtureRepoPath,
      configuration: .debug,
      scratchPath: scratchPath
    )
    let buildResult = try runner.produceIndexStore()

    // Compile test targets into the SAME index store (same scratch path) so the fixture's
    // test-target category is indexed too. Fixed argument vector; failure is a fixture bug.
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

  /// Serializes the index to a temp `.scip` file and runs `scip lint <path>` with a fixed
  /// argument vector. Zero errors means: exit code 0 AND no `error:`-prefixed findings.
  private static func lintExpectingZeroErrors(_ index: Scip_Index, fixtureName: String) throws {
    let scip = try ScipCLIGate.locateScipBinary()

    let workDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(atPath: workDirectory) }
    let indexPath = (workDirectory as NSString).appendingPathComponent("\(fixtureName).scip")
    try index.serializedData().write(to: URL(fileURLWithPath: indexPath))

    let result = try SubprocessRunner.run(
      executable: scip,
      arguments: ["lint", indexPath],
      currentDirectory: "/"
    )
    #expect(result.exitCode == 0, "scip lint must exit 0 on the \(fixtureName) index")
    let errorLines = result.combinedOutput
      .split(separator: "\n")
      .filter { $0.hasPrefix("error:") }
    #expect(errorLines.isEmpty, "scip lint reported errors:\n\(errorLines.joined(separator: "\n"))")
  }

  private static func fixtureRepoPath(fixtureName: String) -> String {
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return repoRoot.appendingPathComponent("Fixtures/\(fixtureName)").path
  }

  private static func schemeFixtureGoldensPath() -> String {
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return repoRoot.appendingPathComponent("scip-swiftTests/SchemeFixtureGoldens").path
  }

  /// Relative paths of every regular file under `directory`, recursively, using "/" separators.
  private static func filesRecursively(under directory: String) throws -> [String] {
    let base = URL(fileURLWithPath: directory)
    guard let enumerator = FileManager.default.enumerator(
      at: base, includingPropertiesForKeys: [.isRegularFileKey]
    ) else {
      return []
    }
    var relativePaths: [String] = []
    for case let url as URL in enumerator {
      let values = try url.resourceValues(forKeys: [.isRegularFileKey])
      guard values.isRegularFile == true else { continue }
      relativePaths.append(url.path.replacingOccurrences(of: base.path + "/", with: ""))
    }
    return relativePaths
  }

  /// A short excerpt of the first differing lines between two texts, for failure messages.
  private static func firstDiffLines(between committed: String, and produced: String) -> String {
    let committedLines = committed.split(separator: "\n", omittingEmptySubsequences: false)
    let producedLines = produced.split(separator: "\n", omittingEmptySubsequences: false)
    var excerpts: [String] = []
    var shown = 0
    for (offset, pair) in zip(committedLines, producedLines).enumerated() {
      if pair.0 != pair.1 {
        excerpts.append("line \(offset + 1): golden  ⟶ \(pair.0)")
        excerpts.append("line \(offset + 1): output ⟶ \(pair.1)")
        shown += 1
        if shown == 5 { break }
      }
    }
    if committedLines.count != producedLines.count {
      excerpts.append("line counts differ: golden \(committedLines.count) vs output \(producedLines.count)")
    }
    return excerpts.isEmpty ? "(contents equal)" : excerpts.joined(separator: "\n")
  }

  private static func makeTemporaryDirectory() throws -> String {
    let path = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("scip-swift-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }
}
