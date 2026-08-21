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

  @Test("HierarchiesFixture index passes scip lint")
  func hierarchiesFixturePassesLint() throws {
    // REL-01 / D-24 (04-01): the relationship fixture's same-package conformances must
    // lint clean from the first commit — every relationship target exists as a document
    // symbol. External-protocol conformance content is deliberately 04-02 scope, where
    // relationship-target minting makes it lint-safe (04-01 flagged assumption).
    let index = try Self.buildIndex(fixtureName: "HierarchiesFixture")
    try Self.lintExpectingZeroErrors(index, fixtureName: "HierarchiesFixture")
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

  @Test("toolchain drift guard fires on a mismatched swift --version (CI 6.3.3 shape)")
  func driftGuardFiresOnVersionMismatch() throws {
    // T-02-10 (02-04): the exact drift observed in engine CI run 32067964049 — goldens
    // generated under the 6.2.4 pin, runner building with 6.3.3. The guard input is an
    // injectable string so the mismatch case needs no foreign toolchain installed.
    let mismatchedOutput =
      "swift-driver version: 1.145.2 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.11 clang-1700.6.54)\n"
      + "Target: arm64-apple-macosx26.0"
    do {
      try ToolchainDriftGuard.enforcePin(versionOutput: mismatchedOutput)
      Issue.record("the guard must throw on a mismatched toolchain version")
    } catch let error as ToolchainDriftError {
      let message = String(describing: error)
      // The message must be immediately actionable: name both versions and every remedy —
      // the pin file, toolchain switching, intentional regeneration, the README boundary.
      #expect(message.contains("6.3.3"), "must name the running version: \(message)")
      #expect(
        message.contains(ToolchainInfo.pinnedSwiftVersion),
        "must name the pinned version: \(message)")
      #expect(message.contains(".swift-version"), "must name the pin file: \(message)")
      #expect(message.contains("xcode-select"), "must name toolchain switching: \(message)")
      #expect(message.contains("DEVELOPER_DIR"), "must name DEVELOPER_DIR switching: \(message)")
      #expect(message.contains("UPDATE_GOLDENS=1"), "must name the regeneration path: \(message)")
      #expect(message.contains("Known limitations"), "must name the README section: \(message)")
    }

    // Unparsable output fails closed — never a lenient parse that could accept the wrong
    // toolchain (T-02-12) — and the message shows the raw first line.
    let unparsableOutput = "some future swift --version shape without the marker"
    do {
      try ToolchainDriftGuard.enforcePin(versionOutput: unparsableOutput)
      Issue.record("the guard must fail closed on unparsable swift --version output")
    } catch let error as ToolchainDriftError {
      #expect(
        String(describing: error).contains("some future swift --version shape"),
        "must show the raw first line: \(error)")
    }
  }

  @Test("running toolchain matches the pinned Swift version")
  func runningToolchainMatchesPinnedSwiftVersion() throws {
    // The live half of the drift guard (T-02-10): CI enforces the pin via the workflow's
    // select-and-verify step, and this re-asserts it inside the suite so a red golden diff
    // is immediately diagnosable as environment drift vs real regression. enforcePin
    // extracts the "Apple Swift version X.Y.Z (" shape, asserts equality with the pin, and
    // fails closed (raw first line shown) on unparsable output.
    let swift = try SubprocessRunner.resolveExecutable(named: "swift")
    let result = try SubprocessRunner.run(
      executable: swift,
      arguments: ["--version"],
      currentDirectory: "/"
    )
    #expect(result.exitCode == 0, "swift --version must exit 0")
    try ToolchainDriftGuard.enforcePin(versionOutput: result.combinedOutput)
  }

  @Test("ToolchainInfo.pinnedSwiftVersion matches the .swift-version file")
  func pinnedSwiftVersionConstantMatchesSwiftVersionFile() throws {
    // Same cross-check posture as D-14's scipCliVersion pin (scipBinaryVersionMatches-
    // EnginePin above): the engine constant and the repo pin file must agree — drift fails
    // the suite here rather than surprising CI.
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let pinFile = repoRoot.appendingPathComponent(".swift-version")
    let contents = try String(contentsOf: pinFile, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(
      contents == ToolchainInfo.pinnedSwiftVersion,
      "ToolchainInfo.pinnedSwiftVersion (\(ToolchainInfo.pinnedSwiftVersion)) != .swift-version (\(contents))"
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
    try Self.snapshotGoldensMatch(
      fixtureName: "SchemeFixture", goldensDirectory: Self.schemeFixtureGoldensPath())
  }

  @Test("HierarchiesFixture snapshot goldens match scip snapshot output")
  func hierarchiesFixtureSnapshotGoldensMatch() throws {
    // REL-01 / SC1 / SC4 (04-01): the relationship fixture's caret goldens — the
    // `relationship <sym> implementation reference` lines under witness definitions
    // are the SC1 visibility surface for the witness baseline.
    try Self.snapshotGoldensMatch(
      fixtureName: "HierarchiesFixture", goldensDirectory: Self.hierarchiesFixtureGoldensPath())
  }

  /// The snapshot-gate harness both fixture rows share (D-13 / A6): `scip snapshot`
  /// has no verify mode — the CLI writes caret-annotated files, and this harness owns
  /// the directory diff against the committed goldens. Set UPDATE_GOLDENS=1 to
  /// regenerate the committed goldens after an intentional emission change (documented
  /// in the README).
  ///
  /// `--strict=false` is deliberate: the pinned v0.9.0 CLI's strict mode wraps every
  /// document result unconditionally (even nil errors), so `scip snapshot` with its
  /// default --strict=true fails on ANY index — a known upstream bug (scip-code/scip
  /// cmd/scip/snapshot.go strict OnError), logged in the orchestrator repo's
  /// deferred-items. Lenient formatting renders our all-canonical symbols identically;
  /// symbol canonicality itself is already gated by `scip lint`.
  private static func snapshotGoldensMatch(
    fixtureName: String, goldensDirectory: String
  ) throws {
    let index = try Self.buildIndex(fixtureName: fixtureName)
    let scip = try ScipCLIGate.locateScipBinary()
    let fixtureRepoPath = Self.fixtureRepoPath(fixtureName: fixtureName)

    let workDirectory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(atPath: workDirectory) }
    let indexPath = (workDirectory as NSString).appendingPathComponent("\(fixtureName).scip")
    try index.serializedData().write(to: URL(fileURLWithPath: indexPath))
    let outputDirectory = (workDirectory as NSString).appendingPathComponent("snapshot")

    let result = try SubprocessRunner.run(
      executable: scip,
      arguments: [
        "snapshot", "--strict=false", "--from", indexPath, "--to", outputDirectory,
        "--project-root", fixtureRepoPath,
      ],
      currentDirectory: "/"
    )
    #expect(result.exitCode == 0, "scip snapshot must exit 0: \(result.combinedOutput)")

    if ProcessInfo.processInfo.environment["UPDATE_GOLDENS"] == "1" {
      try? FileManager.default.removeItem(atPath: goldensDirectory)
      try FileManager.default.createDirectory(
        atPath: (goldensDirectory as NSString).deletingLastPathComponent,
        withIntermediateDirectories: true)
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
        "golden file sets differ — missing from output: \(missing), unexpected: \(extra). Intentional change? Regenerate with UPDATE_GOLDENS=1."
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

  @Test("symbol-table.json matches the engine's mapper output (parity contract)")
  func symbolTableMatchesMapperOutput() throws {
    // D-08 half 2: Fixtures/SchemeFixture/symbol-table.json is a cross-repo data contract —
    // the orchestrator repo's Go namer oracle (swift/internal/symbol) replays these records
    // through Symbol(SymbolInput) and asserts byte-equal output. Field names align 1:1 with
    // the Go SymbolInput so neither side needs translation logic. Overload indices come from
    // the REAL OverloadTable (source order), never hand-invented. Regenerate intentionally
    // with UPDATE_SYMBOL_TABLE=1 (documented in the README).
    let fixtureRepoPath = Self.fixtureRepoPath(fixtureName: "SchemeFixture")
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

    let indexStoreDB = try IndexStoreLoader.open(
      storePath: buildResult.indexStorePath,
      databasePath: (workDirectory as NSString).appendingPathComponent("index-db"))
    indexStoreDB.pollForUnitChangesAndWait()

    // The definitions pre-pass, mirroring SCIPIndexBuilder's Phase A (D-07): one Definition
    // per non-local definition occurrence, grouped and ordered by source position.
    var definitions: [OverloadTable.Definition] = []
    for filePath in SwiftFileDiscovery.swiftFiles(underRepoPath: fixtureRepoPath) {
      for occurrence in indexStoreDB.symbolOccurrences(inFilePath: filePath)
      where occurrence.roles.contains(.definition)
        && !occurrence.symbol.properties.contains(.local)
      {
        guard let parsed = USRSymbolParser.parse(occurrence.symbol.usr),
          let kind = USRSymbolMapper.declKind(for: occurrence.symbol),
          let name = USRSymbolMapper.sourceName(parsed: parsed, symbol: occurrence.symbol)
        else { continue }
        definitions.append(
          OverloadTable.Definition(
            usr: occurrence.symbol.usr,
            module: parsed.module,
            containerNames: parsed.containers.map(\.name),
            name: name,
            kind: kind,
            relativePath: String(filePath.dropFirst(fixtureRepoPath.count + 1)),
            line: occurrence.location.line,
            utf8Column: occurrence.location.utf8Column
          ))
      }
    }
    let overloadTable = OverloadTable(definitions: definitions)

    // One record per distinct definition symbol that maps canonically (D-06 fallback
    // symbols have no SymbolInput and are not part of the parity contract).
    var records: [Self.SymbolTableRecord] = []
    var seenUSRs = Set<String>()
    for filePath in SwiftFileDiscovery.swiftFiles(underRepoPath: fixtureRepoPath) {
      for occurrence in indexStoreDB.symbolOccurrences(inFilePath: filePath)
      where occurrence.roles.contains(.definition)
        && !occurrence.symbol.properties.contains(.local)
      {
        guard seenUSRs.insert(occurrence.symbol.usr).inserted,
          let parsed = USRSymbolParser.parse(occurrence.symbol.usr),
          let identity = USRSymbolMapper.resolvedIdentity(parsed: parsed, symbol: occurrence.symbol),
          let expected = USRSymbolMapper.canonicalSymbolString(
            parsed: parsed,
            symbol: occurrence.symbol,
            isSystemLocation: occurrence.location.isSystem,
            toolchainVersion: ToolchainInfo.pinnedSwiftVersion,
            overloadIndex: overloadTable.index(forUSR: occurrence.symbol.usr)
          )
        else { continue }

        let isSystem = parsed.isSystemModule || occurrence.location.isSystem
        records.append(
          Self.SymbolTableRecord(
            module: parsed.module,
            isSystem: isSystem,
            swiftToolchainVersion: isSystem ? ToolchainInfo.pinnedSwiftVersion : "",
            containers: parsed.containers.map {
              .init(name: $0.name, kind: Self.kindName($0.kind))
            },
            name: identity.name,
            kind: Self.kindName(identity.kind),
            overloadIndex: overloadTable.index(forUSR: occurrence.symbol.usr),
            expectedSymbol: expected
          ))
      }
    }
    records.sort {
      $0.expectedSymbol != $1.expectedSymbol
        ? $0.expectedSymbol < $1.expectedSymbol : $0.overloadIndex < $1.overloadIndex
    }
    #expect(!records.isEmpty, "the fixture must produce canonical definition records")
    #expect(
      records.contains { $0.overloadIndex > 0 },
      "the table must include real (+N) overload indices from the OverloadTable"
    )
    #expect(
      records.contains { $0.isSystem },
      "the table must include the retroactive system-module record"
    )

    let tablePath = (fixtureRepoPath as NSString).appendingPathComponent("symbol-table.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let encoded = try encoder.encode(records)

    if ProcessInfo.processInfo.environment["UPDATE_SYMBOL_TABLE"] == "1" {
      try encoded.write(to: URL(fileURLWithPath: tablePath))
      return
    }

    guard let committed = try? Data(contentsOf: URL(fileURLWithPath: tablePath)) else {
      Issue.record(
        "missing \(tablePath) — run UPDATE_SYMBOL_TABLE=1 swift test to generate it")
      return
    }
    let committedRecords = try JSONDecoder().decode([Self.SymbolTableRecord].self, from: committed)
    if committedRecords != records {
      let committedSet = Set(committedRecords)
      let recordSet = Set(records)
      let missing = records.filter { !committedSet.contains($0) }
      let stale = committedRecords.filter { !recordSet.contains($0) }
      Issue.record(
        "symbol-table.json is stale — regenerate with UPDATE_SYMBOL_TABLE=1 if the change is intentional. New/changed: \(missing.prefix(3)); removed: \(stale.prefix(3))"
      )
    }
  }

  // MARK: - Shared gate plumbing

  /// One record of the cross-repo parity symbol table (D-08): field names align 1:1 with the
  /// Go namer's `SymbolInput` (swift/internal/symbol/namer.go) so the Go parity test needs no
  /// translation logic.
  struct SymbolTableRecord: Codable, Equatable, Hashable {
    struct Container: Codable, Equatable, Hashable {
      let name: String
      let kind: String
    }

    let module: String
    let isSystem: Bool
    let swiftToolchainVersion: String
    let containers: [Container]
    let name: String
    let kind: String
    let overloadIndex: Int
    let expectedSymbol: String
  }

  /// The wire names of the 22 DeclKind families — mirrored by the Go parity test's kind map.
  private static func kindName(_ kind: DeclKind) -> String {
    switch kind {
    case .module: return "module"
    case .struct: return "struct"
    case .class: return "class"
    case .enum: return "enum"
    case .protocol: return "protocol"
    case .typeAlias: return "typeAlias"
    case .func: return "func"
    case .method: return "method"
    case .operator: return "operator"
    case .constructor: return "constructor"
    case .destructor: return "destructor"
    case .getter: return "getter"
    case .setter: return "setter"
    case .property: return "property"
    case .constant: return "constant"
    case .variable: return "variable"
    case .subscript: return "subscript"
    case .enumCase: return "enumCase"
    case .protocolMethod: return "protocolMethod"
    case .typeParameter: return "typeParameter"
    case .parameter: return "parameter"
    case .macro: return "macro"
    }
  }

  /// Errors when the `scip` binary cannot be located. The message names both resolution
  /// options so a human can fix the environment; the gate tests fail on this, never skip.
  struct ScipBinaryMissingError: Error, CustomStringConvertible {
    var description: String {
      "scip CLI not found: set SCIP_BIN to the scip binary path, or install scip "
        + "(https://github.com/scip-code/scip) so it is on PATH"
    }
  }

  /// Requirement: T-02-10/T-02-11/T-02-12 (02-04) — thrown when the running Swift toolchain
  /// does not match the engine's `.swift-version` pin. The committed snapshot goldens embed
  /// toolchain-dependent content (Swift Testing synthesized accessor USRs carry
  /// toolchain-dependent hash suffixes; newer toolchains emit extra stdlib interpolation
  /// occurrences such as `DefaultStringInterpolation.appendLiteral/appendPart`), so a
  /// mismatch means a golden diff is environment drift, not a regression. The message names
  /// every remedy so the failure is immediately actionable.
  struct ToolchainDriftError: Error, CustomStringConvertible {
    /// The version extracted from `swift --version`, or nil when the output was unparsable
    /// (the guard then fails closed, showing the raw first line).
    let runningVersion: String?
    let pinnedVersion: String
    let rawFirstLine: String

    var description: String {
      let running = runningVersion.map { "Apple Swift version \($0)" }
        ?? "(unparsed `swift --version` output — first line: \(rawFirstLine))"
      return "Swift toolchain drift: running \(running), but the engine pin (.swift-version) "
        + "is \(pinnedVersion). The committed snapshot goldens are reproducible ONLY under "
        + "the pinned toolchain — a red golden diff on a different toolchain is environment "
        + "drift, not a regression. Switch to the pinned toolchain (xcode-select -s <the "
        + "Xcode shipping Swift \(pinnedVersion)>, or export DEVELOPER_DIR=<that "
        + "Xcode>/Contents/Developer), or, after an intentional pin bump, regenerate the "
        + "goldens with UPDATE_GOLDENS=1 under the new toolchain. See the \"Known "
        + "limitations\" section of README.md (golden reproducibility boundary)."
    }
  }

  enum ToolchainDriftGuard {
    /// Extracts the running Swift version from `swift --version` output. The parse is
    /// anchored on the exact `Apple Swift version X.Y.Z (` shape (T-02-12): the version is
    /// the digit/dot run between the marker and the literal ` (` anchor — so `6.2.4` can
    /// never match a `6.2.40`-style suffix, and anything unparsable returns nil so the
    /// caller fails closed rather than accepting the wrong toolchain leniently.
    static func runningSwiftVersion(in versionOutput: String) -> String? {
      let marker = "Apple Swift version "
      guard let markerRange = versionOutput.range(of: marker) else { return nil }
      let remainder = versionOutput[markerRange.upperBound...]
      guard let anchorRange = remainder.range(of: " (") else { return nil }
      let version = remainder[..<anchorRange.lowerBound]
      guard !version.isEmpty, version.allSatisfy({ $0.isNumber || $0 == "." }) else {
        return nil
      }
      return String(version)
    }

    /// Compares the running toolchain against the pin (T-02-10/T-02-11). Throws
    /// `ToolchainDriftError` on mismatch or unparsable output — never a silent pass. The
    /// version output is an injectable string so the mismatch case is testable without a
    /// foreign toolchain installed.
    static func enforcePin(
      versionOutput: String,
      pinnedVersion: String = ToolchainInfo.pinnedSwiftVersion
    ) throws {
      let firstLine = versionOutput.split(separator: "\n").first.map(String.init)
        ?? versionOutput
      let running = runningSwiftVersion(in: versionOutput)
      guard running == pinnedVersion else {
        throw ToolchainDriftError(
          runningVersion: running,
          pinnedVersion: pinnedVersion,
          rawFirstLine: firstLine
        )
      }
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

  private static func hierarchiesFixtureGoldensPath() -> String {
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return repoRoot.appendingPathComponent("scip-swiftTests/HierarchiesFixtureGoldens").path
  }

  /// Relative paths of every regular file under `directory`, recursively, using "/" separators.
  private static func filesRecursively(under directory: String) throws -> [String] {
    // Resolve symlinks on both sides: NSTemporaryDirectory() lives behind macOS's /private
    // symlink, and a raw enumerator would otherwise yield non-prefixable paths.
    let base = URL(fileURLWithPath: directory).resolvingSymlinksInPath()
    guard let enumerator = FileManager.default.enumerator(
      at: base, includingPropertiesForKeys: [.isRegularFileKey]
    ) else {
      return []
    }
    var relativePaths: [String] = []
    for case let url as URL in enumerator {
      let values = try url.resourceValues(forKeys: [.isRegularFileKey])
      guard values.isRegularFile == true else { continue }
      let path = url.resolvingSymlinksInPath().path
      guard path.hasPrefix(base.path + "/") else { continue }
      relativePaths.append(String(path.dropFirst(base.path.count + 1)))
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
