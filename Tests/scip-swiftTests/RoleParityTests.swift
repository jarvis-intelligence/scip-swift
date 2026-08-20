import Foundation
import Testing

@testable import scip_swift

/// Requirement: NAV-01 / D-15 / D-16 (03-01) — the programmatic role oracle.
///
/// `scip snapshot` renders only four role words — definition, forward_definition,
/// synthetic_definition, reference (orchestrator repo
/// `bindings/go/scip/testutil/format.go:137-145`) — so the caret goldens can anchor
/// positions and symbols but can NEVER show ReadAccess/WriteAccess bits. This suite is
/// the only role oracle the phase has (D-15's programmatic half is load-bearing, not
/// supplementary).
///
/// D-16 is frozen as the contract under test, in `SymbolRoleMapping.scipRoles`:
/// `.write` → WriteAccess; else `.reference`/`.read` → ReadAccess; else no access bit
/// (definitions and declarations emit definition/forward-definition bits only). The
/// store's `.call`/`.dynamic`/`.addressOf` contribute nothing to access bits.
///
/// Occurrence families proven over the SchemeFixture corpus (all lines 0-based, resolved
/// structurally from the fixture sources — never copied from probe output):
/// - property writes (8 sites, asserted in BOTH directions),
/// - property/param/subscript reads (both directions over the read families),
/// - params on both symbol paths (clean `local n` symbols and D-06 fallback Terms),
/// - enum-case / type / function references (ReadAccess via the `.reference` clause),
/// - accessors incl. willSet (ReadAccess or Definition, never WriteAccess),
/// - definitions (Definition bit, no access bit, never with ForwardDefinition).
///
/// `UPDATE_ROLE_TABLE=1` regenerates the committed expectation table
/// `Fixtures/SchemeFixture/role-table.json` (same env-hook discipline as
/// UPDATE_GOLDENS/UPDATE_SYMBOL_TABLE; regenerate only under the pinned toolchain).
/// The table is scoped to the pinned expectation families below — the in-code
/// both-directions sweeps remain the exhaustive oracle.
@Suite("RoleParity")
struct RoleParityTests {

  // MARK: - Task 1 (tracer): end-to-end WriteAccess proof over property writes

  @Test("WriteAccess occurs exactly at the eleven property-write sites (both directions)")
  func writeAccessExactSites() throws {
    let index = try Self.sharedIndex()
    let lib = try Self.sourcesFixture()
    let test = try Self.testsFixture()

    // Every expected write site: (document, unique assignment-target text, written
    // property's symbol). Line numbers are resolved from the fixture source at runtime.
    let expectedSites: [(Fixture, String, String)] = [
      // Sources/SchemeFixture/SchemeFixture.swift — five library writes.
      (lib, "self.x = x", Family.vecX),
      (lib, "self.y = y", Family.vecY),
      (lib, "self.content = content", Family.boxContent),
      (lib, "backing = newValue", Family.observedBacking),
      (lib, "prepared = true", Family.observedPrepared),
      // Deep-nesting section (03-02): the stored-property init assignment, the
      // computed property's setter writing its backing storage, and the
      // computed-property write via setter assignment inside reset().
      (lib, "self.metric = metric", Family.coreMetric),
      (lib, "set { metric = newValue }", Family.coreMetric),
      (lib, "calibrated = 0", Family.coreCalibrated),
      // Tests/SchemeFixtureTests/SchemeFixtureTests.swift — three test-file writes.
      (test, #"poster.label = "demo""#, Family.posterLabel),
      (test, "observed.computed = 5", Family.observedComputed),
      (test, "observed.watched = 6", Family.observedWatched),
    ]

    var expected = Set<RowKey>()
    for (fixture, assignment, symbol) in expectedSites {
      let line = try Self.uniqueLine(in: fixture, containing: assignment)
      // The source line really is the expected assignment — structural sanity.
      #expect(
        fixture.lines[Int(line)].contains(assignment),
        "line \(line) of \(fixture.relativePath) must contain '\(assignment)'"
      )
      expected.insert(RowKey(relativePath: fixture.relativePath, line: line, symbol: symbol))
    }
    #expect(expected.count == 11, "the eleven write sites must be distinct")

    // Direction B (sweep): every WriteAccess occurrence in the whole corpus is an
    // expected site. Direction A: every expected site has its WriteAccess occurrence.
    let actual = Set(
      index.allOccurrences
        .filter { $0.symbolRoles & Roles.writeBit != 0 }
        .map { RowKey(relativePath: $0.relativePath, line: $0.line, symbol: $0.symbol) })

    let unexpectedWrites = actual.subtracting(expected).sorted()
    #expect(
      unexpectedWrites.isEmpty,
      "unexpected WriteAccess occurrences: \(unexpectedWrites) — D-16 emits WriteAccess only on property-write sites"
    )
    let missingWrites = expected.subtracting(actual).sorted()
    #expect(
      missingWrites.isEmpty,
      "missing WriteAccess occurrences at expected property-write sites: \(missingWrites)"
    )
  }

  @Test("setter-call occurrences at write anchors carry ReadAccess, never WriteAccess")
  func setterCallsAtWriteAnchorsAreReads() throws {
    let index = try Self.sharedIndex()
    let lib = try Self.sourcesFixture()
    let test = try Self.testsFixture()

    // Each `self.x = x`-style site emits TWO occurrences at the same anchor: the property
    // occurrence (WriteAccess) and the setter-call occurrence (its own symbol string,
    // `.call`-bearing → ReadAccess via the `.reference` clause, never WriteAccess).
    let expectedAdjacency: [(Fixture, String, String)] = [
      (lib, "self.x = x", Family.vecXSetter),
      (lib, "self.y = y", Family.vecYSetter),
      (lib, "self.content = content", Family.boxContentSetter),
      (lib, "backing = newValue", Family.observedBackingSetter),
      (lib, "prepared = true", Family.observedPreparedSetter),
      (lib, "self.metric = metric", Family.coreMetricSetter),
      (lib, "set { metric = newValue }", Family.coreMetricSetter),
      (lib, "calibrated = 0", Family.coreCalibratedSetter),
      (test, #"poster.label = "demo""#, Family.posterLabelSetter),
      (test, "observed.computed = 5", Family.observedComputedSetter),
      (test, "observed.watched = 6", Family.observedWatchedSetter),
    ]

    for (fixture, assignment, setterSymbol) in expectedAdjacency {
      let line = try Self.uniqueLine(in: fixture, containing: assignment)
      let lineOccurrences = index.occurrences(in: fixture.relativePath, atLine: line)

      guard let write = lineOccurrences.first(where: { $0.symbolRoles & Roles.writeBit != 0 })
      else {
        Issue.record("no WriteAccess occurrence at \(fixture.relativePath):\(line)")
        continue
      }
      guard let setter = lineOccurrences.first(where: { $0.symbol == setterSymbol })
      else {
        Issue.record(
          "missing setter-call occurrence \(setterSymbol) at \(fixture.relativePath):\(line)")
        continue
      }
      // Same anchor, disjoint access bits.
      #expect(
        setter.singleLineRange.startCharacter == write.singleLineRange.startCharacter,
        "setter call must share the write's anchor column at \(fixture.relativePath):\(line)"
      )
      #expect(
        setter.symbolRoles & Roles.readBit != 0,
        "setter-call occurrence must carry ReadAccess (\(setterSymbol))"
      )
      #expect(
        setter.symbolRoles & Roles.writeBit == 0 && setter.symbolRoles & Roles.definitionBit == 0,
        "setter-call occurrence must never carry WriteAccess or Definition (\(setterSymbol))"
      )
    }
  }

  @Test("no occurrence carries ReadAccess and WriteAccess simultaneously")
  func noSimultaneousReadAndWrite() throws {
    let index = try Self.sharedIndex()
    // Exhaustive seed invariant over the whole corpus (definitions/forward-definitions
    // carry no access bit either, so READ+WRITE is the only access-bit co-occurrence).
    let offenders = index.allOccurrences.filter {
      $0.symbolRoles & Roles.readBit != 0 && $0.symbolRoles & Roles.writeBit != 0
    }
    #expect(
      offenders.isEmpty,
      "occurrences carrying Read+Write simultaneously: \(offenders.map(\.symbol).sorted())"
    )
  }

  // MARK: - Task 2: breadth — every occurrence family

  @Test("property/param/subscript reads carry ReadAccess exactly at the expected sites (both directions)")
  func readFamiliesMatchExpectedSites() throws {
    let index = try Self.sharedIndex()
    let lib = try Self.sourcesFixture()
    let ext = try Self.extensionFixture()
    let test = try Self.testsFixture()

    // Pinned read sites, resolved structurally: (fixture, unique source anchor, symbols
    // read there). The anchors name the READ expressions; the source is the truth.
    let expectedReadSites: [(Fixture, String, [String])] = [
      // Property reads.
      (lib, "lhs.x == rhs.x && lhs.y == rhs.y", [Family.vecX, Family.vecY]),
      (lib, "Vec(x: lhs.x + rhs.x, y: lhs.y + rhs.y)", [Family.vecX, Family.vecY]),
      (lib, "index == 0 ? x : y", [Family.vecX, Family.vecY]),
      (lib, "Double(x * x + y * y)", [Family.vecX, Family.vecY]),
      (lib, "get { backing }", [Family.observedBacking]),
      (ext, "abs(x) + abs(y)", [Family.vecX, Family.vecY]),
      (test, "vector.manhattanLength == 3", [Family.vecManhattanLength]),
      (test, "observed.computed == 5 && observed.prepared",
       [Family.observedComputed, Family.observedPrepared]),
      (test, "point.x == 1", [Family.vecX]),
      // Param reads — D-06 fallback Terms (init/param/operator params read at use
      // sites; the RHS of `self.x = x` is a read of the `x` parameter).
      (lib, "self.x = x", [Family.initXParam]),
      (lib, "self.y = y", [Family.initYParam]),
      (lib, "self.content = content", [Family.boxContentParam]),
      (lib, "self.init(x: scalar, y: scalar)", [Family.initScalarParam]),
      (lib, "lhs.x == rhs.x && lhs.y == rhs.y", [Family.eqLhsParam, Family.eqRhsParam]),
      (lib, "Vec(x: lhs.x + rhs.x, y: lhs.y + rhs.y)",
       [Family.plusLhsParam, Family.plusRhsParam]),
      // Subscript read at `vector[0]` — the property Term and the getter Term, both on
      // the test-target module header (CR-01: fallback attribution is location-based).
      (test, "vector[0] == 1", [Family.subscriptTermTests, Family.subscriptGetterTermTests]),
      // Deep-nesting section (03-02): reads of the stored property in the computed
      // getter bodies (the read-only `doubled` and `calibrated`'s get clause).
      (lib, "metric + metric", [Family.coreMetric]),
      (lib, "get { metric }", [Family.coreMetric]),
    ]

    var expected = Set<RowKey>()
    for (fixture, anchor, symbols) in expectedReadSites {
      let line = try Self.uniqueLine(in: fixture, containing: anchor)
      for symbol in symbols {
        expected.insert(RowKey(relativePath: fixture.relativePath, line: line, symbol: symbol))
      }
    }
    // Bare-identifier and interpolated reads resolve via their own anchors.
    let unwrapLine = try Self.uniqueLine(in: lib, trimmedEquals: "content")
    expected.insert(
      RowKey(relativePath: lib.relativePath, line: unwrapLine, symbol: Family.boxContent))
    let drawLine = try Self.uniqueLine(in: lib, containing: #"poster(\(label))"#)
    expected.insert(
      RowKey(relativePath: lib.relativePath, line: drawLine, symbol: Family.posterLabel))


    // Both directions over the read families: every ReadAccess occurrence of a
    // property/param/subscript family symbol sits at an expected site, and every
    // expected site has its ReadAccess occurrence. (`observed.watched` and several
    // param Terms legitimately have no reads at all.)
    let readFamilySymbols = Family.propertyTerms
      .union(Family.paramTerms)
      .union(Family.subscriptTerms)
    let actual = Set(
      index.allOccurrences
        .filter { readFamilySymbols.contains($0.symbol) && $0.symbolRoles & Roles.readBit != 0 }
        .map { RowKey(relativePath: $0.relativePath, line: $0.line, symbol: $0.symbol) })

    let unexpectedReads = actual.subtracting(expected).sorted()
    #expect(
      unexpectedReads.isEmpty,
      "unexpected ReadAccess sites in the read families: \(unexpectedReads)"
    )
    let missingReads = expected.subtracting(actual).sorted()
    #expect(
      missingReads.isEmpty,
      "missing ReadAccess occurrences at expected read sites: \(missingReads)"
    )
  }



  @Test("params are proven on both symbol paths: clean locals and D-06 fallback Terms")
  func paramsBothSymbolPaths() throws {
    let index = try Self.sharedIndex()
    let lib = try Self.sourcesFixture()

    // Clean-local path (top-level func params): both symbols exist as definitions with
    // the Definition bit and no access bit. The store emits no use-site reads for these
    // params on the pinned toolchain (an empirically confirmed store gap — see the
    // 03-01 SUMMARY); should a future toolchain add them, this loop requires them to
    // carry ReadAccess (never WriteAccess) instead of passing vacuously.
    let localRows = index.allOccurrences.filter { $0.symbol.hasPrefix("local ") }
    #expect(!localRows.isEmpty, "the corpus must carry clean `local n` param symbols")
    for row in localRows {
      if row.symbolRoles & Roles.definitionBit != 0 {
        #expect(
          row.symbolRoles & (Roles.readBit | Roles.writeBit) == 0,
          "local param definition must carry no access bit (\(row))"
        )
      } else {
        #expect(
          row.symbolRoles & Roles.readBit != 0 && row.symbolRoles & Roles.writeBit == 0,
          "local param use-site occurrence must be a ReadAccess-only read (\(row))"
        )
      }
    }
    let textLine = try Self.uniqueLine(in: lib, containing: "public func parse(_ text: String)")
    #expect(
      !index.occurrences(in: lib.relativePath, atLine: textLine)
        .filter { $0.symbol == "local text" && $0.symbolRoles & Roles.definitionBit != 0 }
        .isEmpty,
      "`local text` must be defined at parse(_: String)"
    )
    let valueLine = try Self.uniqueLine(in: lib, containing: "public func parse(_ value: Int)")
    #expect(
      !index.occurrences(in: lib.relativePath, atLine: valueLine)
        .filter { $0.symbol == "local value_1" && $0.symbolRoles & Roles.definitionBit != 0 }
        .isEmpty,
      "`local value_1` must be defined at parse(_: Int)"
    )

    // Fallback-Term path: real use-site reads exist and carry ReadAccess (proven
    // exhaustively in readFamiliesMatchExpectedSites; this asserts the family is live).
    let paramTermReads = index.allOccurrences.filter {
      Family.paramTerms.contains($0.symbol) && $0.symbolRoles & Roles.readBit != 0
    }
    #expect(
      !paramTermReads.isEmpty,
      "D-06 fallback-Term params must have use-site ReadAccess occurrences"
    )
  }

  @Test("enum-case, type, and function references carry ReadAccess; definitions carry none")
  func enumTypeAndFunctionReferences() throws {
    let index = try Self.sharedIndex()
    let lib = try Self.sourcesFixture()
    let test = try Self.testsFixture()
    let systemPrefix = "scip-swift swift Swift \(ToolchainInfo.pinnedSwiftVersion) "

    func expectRead(at fixture: Fixture, anchor: String, symbol: String) throws {
      let line = try Self.uniqueLine(in: fixture, containing: anchor)
      let hits = index.occurrences(in: fixture.relativePath, atLine: line)
        .filter { $0.symbol == symbol && $0.symbolRoles & Roles.readBit != 0 }
      #expect(
        !hits.isEmpty,
        "\(symbol) must carry ReadAccess via the .reference clause at \(fixture.relativePath):\(line)"
      )
    }

    func expectDefinition(at fixture: Fixture, anchor: String, symbol: String) throws {
      let line = try Self.uniqueLine(in: fixture, containing: anchor)
      let hits = index.occurrences(in: fixture.relativePath, atLine: line)
        .filter { $0.symbol == symbol && $0.symbolRoles & Roles.definitionBit != 0 }
      #expect(
        !hits.isEmpty,
        "\(symbol) must be defined at \(fixture.relativePath):\(line)"
      )
      #expect(
        hits.allSatisfy { $0.symbolRoles & (Roles.readBit | Roles.writeBit) == 0 },
        "definitions must carry no access bit (\(symbol))"
      )
    }

    // Enum-case references (store roles [ref|contBy] — no .read bit; ReadAccess arrives
    // via D-16's .reference clause) and the enum type reference at the same site.
    try expectRead(at: test, anchor: "Spectrum.red != Spectrum.blue", symbol: Family.spectrumRed)
    try expectRead(at: test, anchor: "Spectrum.red != Spectrum.blue", symbol: Family.spectrumBlue)
    try expectRead(at: test, anchor: "Spectrum.red != Spectrum.blue", symbol: Family.spectrumType)
    try expectDefinition(at: lib, anchor: "case red", symbol: Family.spectrumRed)
    try expectDefinition(at: lib, anchor: "case blue", symbol: Family.spectrumBlue)
    try expectDefinition(at: lib, anchor: "case green", symbol: Family.spectrumGreen)

    // Type references: constructor positions, conformances, annotations, typealiases.
    try expectRead(at: test, anchor: "let vector = Vec(x: 1, y: 2)", symbol: Family.vecType)
    try expectRead(at: test, anchor: "let poster = Poster()", symbol: Family.posterType)
    try expectRead(at: test, anchor: "let observed = Observed()", symbol: Family.observedType)
    try expectRead(at: test, anchor: "let point: Point = vector", symbol: Family.pointType)
    try expectRead(at: test, anchor: "Box(content: vector).describe()", symbol: Family.boxType)
    try expectRead(at: lib, anchor: "public final class Poster: Drawable {", symbol: Family.drawableType)
    try expectDefinition(at: lib, anchor: "public struct Vec {", symbol: Family.vecType)
    try expectDefinition(at: lib, anchor: "public typealias Point = Vec", symbol: Family.pointType)

    // Function/method references (store roles [ref|call] — the call bit contributes
    // nothing; ReadAccess arrives via the .reference clause).
    try expectRead(at: test, anchor: "let vector = Vec(x: 1, y: 2)", symbol: Family.vecInit)
    try expectRead(at: test, anchor: "let scalar = Vec(scalar: 3)", symbol: Family.vecInitPlusOne)
    try expectRead(at: test, anchor: "vector + scalar", symbol: Family.vecPlus)
    try expectRead(at: test, anchor: #"parse("7") == 7"#, symbol: Family.parseText)
    try expectRead(at: test, anchor: "parse(7)", symbol: Family.parseInt)
    try expectRead(at: test, anchor: "vector.length() > 0", symbol: Family.vecLength)
    try expectRead(at: test, anchor: "Box(content: vector).describe()", symbol: Family.boxDescribe)
    try expectRead(at: test, anchor: "Box(content: vector).unwrap()", symbol: Family.boxUnwrap)
    try expectRead(at: test, anchor: "schemeShout()", symbol: systemPrefix + "String#schemeShout().")
    try expectRead(at: test, anchor: "conditionallyCompiled()", symbol: Family.conditionallyCompiled)
    try expectRead(at: test, anchor: "let poster = Poster()", symbol: Family.posterInit)
    try expectRead(at: test, anchor: "poster.draw()", symbol: Family.posterDraw)
    try expectRead(at: test, anchor: "let observed = Observed()", symbol: Family.observedInit)
    try expectDefinition(at: lib, anchor: "public func parse(_ text: String)", symbol: Family.parseText)
    try expectDefinition(at: lib, anchor: "public func parse(_ value: Int)", symbol: Family.parseInt)
  }

  @Test("accessor occurrences (getter/setter/willSet) never carry WriteAccess")
  func accessorFamilyNeverWrites() throws {
    let index = try Self.sharedIndex()
    let lib = try Self.sourcesFixture()

    let rows = index.allOccurrences.filter { Family.accessorTerms.contains($0.symbol) }
    #expect(!rows.isEmpty, "the corpus must carry accessor-family occurrences")
    for row in rows {
      #expect(
        row.symbolRoles & Roles.writeBit == 0,
        "accessor occurrence must never carry WriteAccess (\(row))"
      )
      if row.symbolRoles & Roles.definitionBit != 0 {
        #expect(
          row.symbolRoles & Roles.readBit == 0,
          "accessor definition must carry no access bit (\(row))"
        )
      } else {
        #expect(
          row.symbolRoles & Roles.readBit != 0,
          "non-definition accessor occurrence must carry ReadAccess (\(row))"
        )
      }
    }

    // The willSet accessor for `watched` is present as a definition in the setter-family
    // `watched=`(+1) form (subKind-driven), at the willSet keyword.
    let willSetLine = try Self.uniqueLine(in: lib, containing: "willSet {")
    let willSetDefinitions = index.occurrences(in: lib.relativePath, atLine: willSetLine)
      .filter { $0.symbol == Family.watchedWillSet && $0.symbolRoles & Roles.definitionBit != 0 }
    #expect(
      !willSetDefinitions.isEmpty,
      "the willSet definition \(Family.watchedWillSet) must exist at the willSet block"
    )
  }

  @Test("definitions carry no access bit and never coexist with ForwardDefinition")
  func definitionsSweep() throws {
    let index = try Self.sharedIndex()
    let definitions = index.allOccurrences.filter { $0.symbolRoles & Roles.definitionBit != 0 }
    #expect(definitions.count >= 50, "the corpus must carry a real definition population")
    let offenders = definitions.filter {
      $0.symbolRoles & (Roles.readBit | Roles.writeBit) != 0
    }
    #expect(
      offenders.isEmpty,
      "definitions carrying access bits: \(offenders.map(\.symbol).sorted())"
    )

    // `.declaration` (→ ForwardDefinition) never fires on this corpus, and the
    // coexistence rule holds vacuously-but-explicitly.
    let forwardDefinitions = index.allOccurrences.filter {
      $0.symbolRoles & Roles.forwardDefinitionBit != 0
    }
    #expect(
      forwardDefinitions.isEmpty,
      "ForwardDefinition occurrences: \(forwardDefinitions.map(\.symbol).sorted())"
    )
    #expect(
      index.allOccurrences.allSatisfy {
        !($0.symbolRoles & Roles.definitionBit != 0
          && $0.symbolRoles & Roles.forwardDefinitionBit != 0)
      },
      "no occurrence may carry Definition and ForwardDefinition together"
    )
  }

  @Test("role-table.json matches the built index for every pinned expectation family (D-15)")
  func roleTableMatchesBuiltIndex() throws {
    let index = try Self.sharedIndex()

    // One row per (document, line, startCharacter, symbol) occurrence of the pinned
    // expectation families — the hand-reviewable golden. Deterministic: sorted by
    // relativePath, line, startCharacter, symbol.
    let rows = index.allOccurrences
      .filter { Family.closedFamilySymbols.contains($0.symbol) }
      .map { RoleTableRow($0) }
      .sorted()

    let tablePath = (Self.fixtureRepoPath() as NSString)
      .appendingPathComponent("role-table.json")

    if ProcessInfo.processInfo.environment["UPDATE_ROLE_TABLE"] == "1" {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(rows).write(to: URL(fileURLWithPath: tablePath))
      return
    }

    guard let committed = try? Data(contentsOf: URL(fileURLWithPath: tablePath)) else {
      Issue.record(
        "missing \(tablePath) — run UPDATE_ROLE_TABLE=1 swift test --filter RoleParity to generate it"
      )
      return
    }
    let committedRows = try JSONDecoder().decode([RoleTableRow].self, from: committed)

    // D-15 sanity gates before comparing: non-empty, carries the WriteAccess family,
    // carries rows for BOTH param symbol paths, and stays within a sane band of the
    // corpus occurrence count.
    #expect(!committedRows.isEmpty, "the committed role table must not be empty")
    #expect(
      committedRows.contains { $0.symbolRoles & Roles.writeBit != 0 },
      "the table must contain at least one WriteAccess row"
    )
    #expect(
      committedRows.contains { $0.symbol.hasPrefix("local ") },
      "the table must contain a clean `local n` param row"
    )
    #expect(
      committedRows.contains { row in
        Family.paramTerms.contains(row.symbol)
          && row.symbolRoles & Roles.readBit != 0
      },
      "the table must contain a D-06 fallback-Term param read row"
    )
    #expect(
      committedRows.count >= 40 && committedRows.count <= index.allOccurrences.count,
      "table row count \(committedRows.count) is outside the sane band [40, \(index.allOccurrences.count)]"
    )


    // Both directions: the built rows for the pinned families equal the committed rows.
    if Set(committedRows) != Set(rows) {
      let committedSet = Set(committedRows)
      let rowSet = Set(rows)
      let missing = rowSet.subtracting(committedSet).sorted().prefix(5)
      let stale = committedSet.subtracting(rowSet).sorted().prefix(5)
      Issue.record(
        "role-table.json is stale — regenerate with UPDATE_ROLE_TABLE=1 under the pinned toolchain if the change is intentional. New/changed: \(missing); removed: \(stale)"
      )
    }
  }

  // MARK: - Role bits (Scip_SymbolRole raw values: definition=1, writeAccess=4,
  // MARK:   readAccess=8, forwardDefinition=64 — Generated/Scip.pb.swift:180-202).

  private enum Roles {
    static let definitionBit: Int32 = Int32(Scip_SymbolRole.definition.rawValue)
    static let writeBit: Int32 = Int32(Scip_SymbolRole.writeAccess.rawValue)
    static let readBit: Int32 = Int32(Scip_SymbolRole.readAccess.rawValue)
    static let forwardDefinitionBit: Int32 = Int32(Scip_SymbolRole.forwardDefinition.rawValue)
  }

  // MARK: - Pinned expectation families (exact canonical symbol strings)

  /// Exact canonical symbol strings for every occurrence family the role oracle pins.
  /// Hand-reviewable constants — the same strings the caret goldens carry.
  private enum Family {
    static let libraryPrefix = "scip-swift swiftpm SchemeFixture . "
    static let testTargetPrefix = "scip-swift swiftpm SchemeFixtureTests . "

    // Property Terms (vars/lets).
    static let vecX = libraryPrefix + "Vec#x."
    static let vecY = libraryPrefix + "Vec#y."
    static let boxContent = libraryPrefix + "Box#content."
    static let posterLabel = libraryPrefix + "Poster#label."
    static let observedComputed = libraryPrefix + "Observed#computed."
    static let observedBacking = libraryPrefix + "Observed#backing."
    static let observedWatched = libraryPrefix + "Observed#watched."
    static let observedPrepared = libraryPrefix + "Observed#prepared."
    static let vecManhattanLength = libraryPrefix + "Vec#manhattanLength."
    // Deep-nesting section (03-02): Lattice.Cell.Core members + the level-1/2 lets.
    static let coreMetric = libraryPrefix + "Lattice#Cell#Core#metric."
    static let coreCalibrated = libraryPrefix + "Lattice#Cell#Core#calibrated."
    static let coreDoubled = libraryPrefix + "Lattice#Cell#Core#doubled."
    static let latticeOrigin = libraryPrefix + "Lattice#origin."
    static let cellTemplate = libraryPrefix + "Lattice#Cell#template."
    static let propertyTerms: Set<String> = [
      vecX, vecY, boxContent, posterLabel, observedComputed, observedBacking,
      observedWatched, observedPrepared, vecManhattanLength,
      coreMetric, coreCalibrated, coreDoubled, latticeOrigin, cellTemplate,
    ]

    // Accessor method forms: getters (zero-arg method string), setters (`name=`), and
    // the willSet for `watched` (setter-family `watched=`(+1), subKind-driven).
    static let vecXSetter = libraryPrefix + "Vec#`x=`()."
    static let vecYSetter = libraryPrefix + "Vec#`y=`()."
    static let boxContentSetter = libraryPrefix + "Box#`content=`()."
    static let posterLabelSetter = libraryPrefix + "Poster#`label=`()."
    static let observedComputedSetter = libraryPrefix + "Observed#`computed=`()."
    static let observedBackingSetter = libraryPrefix + "Observed#`backing=`()."
    static let observedPreparedSetter = libraryPrefix + "Observed#`prepared=`()."
    static let observedWatchedSetter = libraryPrefix + "Observed#`watched=`()."
    static let coreMetricSetter = libraryPrefix + "Lattice#Cell#Core#`metric=`()."
    static let coreCalibratedSetter = libraryPrefix + "Lattice#Cell#Core#`calibrated=`()."
    static let watchedWillSet = libraryPrefix + "Observed#`watched=`(+1)."
    static let accessorTerms: Set<String> = [
      libraryPrefix + "Vec#x().", libraryPrefix + "Vec#y().",
      libraryPrefix + "Box#content().", libraryPrefix + "Poster#label().",
      libraryPrefix + "Observed#computed().", libraryPrefix + "Observed#backing().",
      libraryPrefix + "Observed#watched().", libraryPrefix + "Observed#prepared().",
      libraryPrefix + "Vec#manhattanLength().",
      // Deep-nesting section (03-02) accessors.
      libraryPrefix + "Lattice#Cell#Core#metric().", coreMetricSetter,
      libraryPrefix + "Lattice#Cell#Core#doubled().",
      libraryPrefix + "Lattice#Cell#Core#calibrated().", coreCalibratedSetter,
      libraryPrefix + "Lattice#origin().", libraryPrefix + "Lattice#`origin=`().",
      libraryPrefix + "Lattice#Cell#template().", libraryPrefix + "Lattice#Cell#`template=`().",
      vecXSetter, vecYSetter, boxContentSetter, posterLabelSetter,
      observedComputedSetter, observedBackingSetter, observedPreparedSetter,
      observedWatchedSetter, watchedWillSet,
    ]

    // Param Terms — D-06 fallback (local-context `A...L_` manglings the parser does not
    // decode; init/param/operator params, each under the canonical module header).
    static let initXParam = libraryPrefix + "`s:13SchemeFixture3VecV1x1yACSi_SitcfcADL_Sivp`."
    static let initYParam = libraryPrefix + "`s:13SchemeFixture3VecV1x1yACSi_SitcfcAEL_Sivp`."
    static let initScalarParam = libraryPrefix + "`s:13SchemeFixture3VecV6scalarACSi_tcfcADL_Sivp`."
    static let eqLhsParam = libraryPrefix + "`s:13SchemeFixture3VecV2eeoiySbAC_ACtFZ3lhsL_ACvp`."
    static let eqRhsParam = libraryPrefix + "`s:13SchemeFixture3VecV2eeoiySbAC_ACtFZ3rhsL_ACvp`."
    static let plusLhsParam = libraryPrefix + "`s:13SchemeFixture3VecV1poiyA2C_ACtFZ3lhsL_ACvp`."
    static let plusRhsParam = libraryPrefix + "`s:13SchemeFixture3VecV1poiyA2C_ACtFZ3rhsL_ACvp`."
    static let boxContentParam = libraryPrefix + "`s:13SchemeFixture3BoxV7contentACyxGx_tcfcADL_xvp`."
    static let paramTerms: Set<String> = [
      initXParam, initYParam, initScalarParam, eqLhsParam, eqRhsParam,
      plusLhsParam, plusRhsParam, boxContentParam,
      libraryPrefix + "`s:13SchemeFixture3VecVyS2icip5indexL_Sivp`.",
    ]

    // Subscript Terms — raw-USR fallback under WR-01, on BOTH module headers: the
    // declarations carry the SchemeFixture header, the test-target use sites carry the
    // SchemeFixtureTests header (CR-01: fallback attribution stays location-based).
    static let subscriptTerm = libraryPrefix + "`s:13SchemeFixture3VecVyS2icip`."
    static let subscriptTermTests = testTargetPrefix + "`s:13SchemeFixture3VecVyS2icip`."
    static let subscriptGetterTerm = libraryPrefix + "`s:13SchemeFixture3VecVyS2icig`."
    static let subscriptGetterTermTests = testTargetPrefix + "`s:13SchemeFixture3VecVyS2icig`."
    static let subscriptTerms: Set<String> = [
      subscriptTerm, subscriptTermTests, subscriptGetterTerm, subscriptGetterTermTests,
    ]

    // Enum-case Terms + the enum type.
    static let spectrumType = libraryPrefix + "Spectrum#"
    static let spectrumRed = libraryPrefix + "Spectrum#red."
    static let spectrumGreen = libraryPrefix + "Spectrum#green."
    static let spectrumBlue = libraryPrefix + "Spectrum#blue."
    static let enumCaseTerms: Set<String> = [spectrumRed, spectrumGreen, spectrumBlue]

    // Type/function symbols pinned at reference sites.
    static let vecType = libraryPrefix + "Vec#"
    static let boxType = libraryPrefix + "Box#"
    static let posterType = libraryPrefix + "Poster#"
    static let observedType = libraryPrefix + "Observed#"
    static let pointType = libraryPrefix + "Point#"
    static let drawableType = libraryPrefix + "Drawable#"
    static let vecInit = libraryPrefix + "Vec#init()."
    static let vecInitPlusOne = libraryPrefix + "Vec#init(+1)."
    static let vecPlus = libraryPrefix + "Vec#+()."
    static let vecLength = libraryPrefix + "Vec#length()."
    static let boxDescribe = libraryPrefix + "Box#describe()."
    static let boxUnwrap = libraryPrefix + "Box#unwrap()."
    static let posterInit = libraryPrefix + "Poster#init()."
    static let posterDraw = libraryPrefix + "Poster#draw()."
    static let observedInit = libraryPrefix + "Observed#init()."
    static let parseText = libraryPrefix + "parse()."
    static let parseInt = libraryPrefix + "parse(+1)."
    static let conditionallyCompiled = libraryPrefix + "conditionallyCompiled()."

    /// Everything the committed role table covers (the table stays scoped to these
    /// pinned families; the in-code sweeps above remain the exhaustive oracle).
    static let closedFamilySymbols: Set<String> =
      propertyTerms
      .union(accessorTerms)
      .union(paramTerms)
      .union(subscriptTerms)
      .union(enumCaseTerms)
      .union(["local text", "local value_1"])
  }

  // MARK: - Built-index plumbing

  /// One flattened occurrence with its document path and 0-based line attached.
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
    }

    func occurrences(in relativePath: String, atLine line: Int32) -> [Scip_Occurrence] {
      (documents[relativePath] ?? []).filter { $0.singleLineRange.line == line }
    }
  }

  /// The built index is cached per test run: every test in this suite asserts over the
  /// same corpus, and one fixture build (a real `swift build --build-tests`) is enough.
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
      let built = BuiltIndex(try RoleParityTests.buildFixtureIndex())
      cached = built
      return built
    }
  }

  /// Mirrors `ScipCLIGateTests.buildIndex` (it is private there): SwiftPMBuildRunner
  /// produces the index store, `swift build --build-tests` folds the test target into
  /// the same store, then the in-process SCIPIndexBuilder emits the Scip_Index.
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

    // Compile test targets into the SAME index store (same scratch path) so the
    // fixture's test-target category is indexed too. Fixed argument vector; failure
    // is a fixture bug.
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
      .appendingPathComponent("scip-swift-role-parity-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }

  // MARK: - Fixture sources (structural line resolution — the source is the truth)

  private struct Fixture {
    let relativePath: String
    let lines: [String]
  }

  private static func sourcesFixture() throws -> Fixture {
    try fixture("Sources/SchemeFixture/SchemeFixture.swift")
  }

  private static func extensionFixture() throws -> Fixture {
    try fixture("Sources/SchemeFixtureExt/SchemeFixtureExt.swift")
  }

  private static func testsFixture() throws -> Fixture {
    try fixture("Tests/SchemeFixtureTests/SchemeFixtureTests.swift")
  }

  private static func fixture(_ relativePath: String) throws -> Fixture {
    let path = (Self.fixtureRepoPath() as NSString).appendingPathComponent(relativePath)
    let text = try String(contentsOfFile: path, encoding: .utf8)
    return Fixture(relativePath: relativePath, lines: text.components(separatedBy: "\n"))
  }




  /// The unique 0-based line in `fixture` whose text contains `anchor`. Refuses
  /// ambiguous anchors — an anchor matching zero or multiple lines is a test bug.
  private static func uniqueLine(in fixture: Fixture, containing anchor: String) throws -> Int32 {
    let matches = fixture.lines.enumerated().filter { $0.element.contains(anchor) }
    guard matches.count == 1, let index = matches.first?.offset else {
      throw RoleParityAnchorError(
        anchor: anchor, file: fixture.relativePath, matchedLines: matches.map(\.offset))
    }
    return Int32(index)
  }

  /// The unique 0-based line in `fixture` whose whitespace-trimmed text equals `needle`.
  private static func uniqueLine(in fixture: Fixture, trimmedEquals needle: String) throws -> Int32 {
    let matches = fixture.lines.enumerated().filter {
      $0.element.trimmingCharacters(in: .whitespaces) == needle
    }
    guard matches.count == 1, let index = matches.first?.offset else {
      throw RoleParityAnchorError(
        anchor: needle, file: fixture.relativePath, matchedLines: matches.map(\.offset))
    }
    return Int32(index)
  }

  private struct RoleParityAnchorError: Error, CustomStringConvertible {
    let anchor: String
    let file: String
    let matchedLines: [Int]
    var description: String {
      "fixture anchor '\(anchor)' in \(file) must match exactly one line, matched lines "
        + "\(matchedLines)"
    }
  }

  // MARK: - Row identity

  /// Identity of one asserted occurrence site for set-level comparisons (line-level —
  /// Swift Testing macro expansion re-anchors duplicate occurrences at shifted columns
  /// on the same line, so startCharacter deliberately stays out of the key).
  private struct RowKey: Hashable, Comparable {
    let relativePath: String
    let line: Int32
    let symbol: String

    static func < (lhs: RowKey, rhs: RowKey) -> Bool {
      if lhs.relativePath != rhs.relativePath { return lhs.relativePath < rhs.relativePath }
      if lhs.line != rhs.line { return lhs.line < rhs.line }
      return lhs.symbol < rhs.symbol
    }
  }

  /// One row of the committed role-expectation table (D-15): a (document, line,
  /// startCharacter, symbol, symbolRoles) site. Codable field names are the stable
  /// contract of the golden file.
  private struct RoleTableRow: Codable, Equatable, Hashable, Comparable {
    let relativePath: String
    let line: Int32
    let startCharacter: Int32
    let symbol: String
    let symbolRoles: Int32

    init(_ occurrence: FlatOccurrence) {
      self.relativePath = occurrence.relativePath
      self.line = occurrence.line
      self.startCharacter = occurrence.startCharacter
      self.symbol = occurrence.symbol
      self.symbolRoles = occurrence.symbolRoles
    }

    static func < (lhs: RoleTableRow, rhs: RoleTableRow) -> Bool {
      if lhs.relativePath != rhs.relativePath { return lhs.relativePath < rhs.relativePath }
      if lhs.line != rhs.line { return lhs.line < rhs.line }
      if lhs.startCharacter != rhs.startCharacter {
        return lhs.startCharacter < rhs.startCharacter
      }
      return lhs.symbol < rhs.symbol
    }
  }
}
