import Foundation
import Testing

@testable import scip_swift

/// Requirement: REL-01 / D-24 (04-01 witness baseline, extended 04-02) — the
/// relationship oracle over HierarchiesFixture.
///
/// Proves BOTH DIRECTIONS over the relationships the engine emits from IndexStoreDB:
/// the byte-stable witness mapping (`.overrideOf` → is_reference + is_implementation,
/// frozen in 04-01 — coverage EXTENDS, never rewrites it, RESEARCH pitfall 10) plus
/// the 04-02 type-level clause edges (baseOf/extendedBy harvest → isImplementation
/// ONLY, scip.proto:477-500 Find-implementations semantics; D-23 carrier for
/// retroactive conformances; D-21 ObjC fallback for the NSObject-rooted superclass
/// gap). Every expected edge IS emitted, and every emitted edge IS expected — no
/// unexpected edges anywhere in the corpus.
///
/// `UPDATE_RELATIONSHIP_TABLE=1` regenerates the committed expectation table
/// `Fixtures/HierarchiesFixture/relationship-table.json` (the fourth env-hook golden —
/// same discipline as UPDATE_GOLDENS/UPDATE_SYMBOL_TABLE/UPDATE_ROLE_TABLE; regenerate
/// only under the pinned toolchain). The in-code both-direction sweeps remain the
/// exhaustive oracle; the table is the hand-reviewable review surface.
@Suite("RelationshipParity")
struct RelationshipParityTests {

  // MARK: - Task 1 (tracer): the 2-level class-override chain, end to end

  @Test("render() overrides carry exactly the two chain edges, both directions")
  func renderOverrideChainIsExact() throws {
    let index = try Self.sharedIndex()

    // The pinned chain (RESEARCH Q1b, byte-stable `.overrideOf` mapping):
    // Square#render() → BaseWidget#render() and RoundedSquare#render() → Square#render(),
    // each isReference == true and isImplementation == true.
    let expected: Set<EdgeKey> = [
      EdgeKey(
        relativePath: Family.hierCorePath,
        symbol: Family.squareRender,
        target: Family.baseWidgetRender,
        isReference: true,
        isImplementation: true),
      EdgeKey(
        relativePath: Family.hierCorePath,
        symbol: Family.roundedSquareRender,
        target: Family.squareRender,
        isReference: true,
        isImplementation: true),
    ]

    // Every relationship in the corpus whose subject is a render() definition: the
    // family is identified structurally (descriptor `render().`), never by container
    // list — a third render override anywhere in the fixture lands in `actual`.
    let actual = Set(
      index.edges
        .filter { Family.renderFamilySubjects.contains($0.symbol) }
        .map(EdgeKey.init))

    // Direction A: every expected chain edge IS emitted.
    let missing = expected.subtracting(actual).sorted()
    #expect(
      missing.isEmpty,
      "missing render-override chain edges: \(missing) — the `.overrideOf` mapping contract broke"
    )
    // Direction B: every render-family edge IS expected — no phantom render edges.
    let unexpected = actual.subtracting(expected).sorted()
    #expect(
      unexpected.isEmpty,
      "unexpected render-family relationship edges: \(unexpected)"
    )
  }

  // MARK: - Task 2: breadth — every witness family both directions

  @Test("every witness-family edge is emitted and every emitted edge is expected")
  func witnessEdgesMatchSourceInventory() throws {
    let index = try Self.sharedIndex()
    let hierCore = try Self.hierCoreFixture()
    let hierExt = try Self.hierExtFixture()

    // The complete witness inventory, generated from the CURRENT emission and
    // hand-reviewed against the fixture source (the D-24 review; RESEARCH pitfall 10 —
    // never author expectations the engine does not already meet). Each row:
    // (document, subject symbol, target symbol, fragment that must appear on the
    // source line where the subject is DEFINED) — witness edges are always
    // is_reference + is_implementation (the byte-stable `.overrideOf` mapping).
    let inventory: [(path: String, fixture: Fixture, symbol: String, target: String, lineFragment: String)] = [
      // Local-protocol witnesses — direct conformances.
      (Family.hierCorePath, hierCore, Family.circleArea, Family.hierShapeArea, "radius * radius"),
      (Family.hierCorePath, hierCore, Family.circleDraw, Family.hierDrawableDraw, "func draw()"),
      (Family.hierCorePath, hierCore, Family.rectArea, Family.hierShapeArea, "width * height"),
      (Family.hierCorePath, hierCore, Family.rectDraw, Family.hierDrawableDraw, "func draw()"),
      (Family.hierCorePath, hierCore, Family.paletteArea, Family.hierShapeArea, "{ 0 }"),
      (Family.hierCorePath, hierCore, Family.paletteDraw, Family.hierDrawableDraw, "func draw()"),
      // Local-protocol witnesses — same-module extension-declared conformance.
      (Family.hierCorePath, hierCore, Family.wheelArea, Family.hierShapeArea, "Double(spokes)"),
      (Family.hierCorePath, hierCore, Family.wheelDraw, Family.hierDrawableDraw, "func draw()"),
      // Conditional-conformance witnesses (raw-USR fallback Terms — pinned as emitted,
      // v1-documented; a future parser rule would change these bytes deliberately).
      (Family.hierCorePath, hierCore, Family.wrapperAreaTerm, Family.hierShapeArea, "inner.area"),
      (Family.hierCorePath, hierCore, Family.wrapperDrawTerm, Family.hierDrawableDraw, "inner.draw()"),
      // The default implementation is itself a witness of the requirement.
      (Family.hierCorePath, hierCore, Family.defaultImplTerm, Family.hierShapeDescribe, "func describe() -> String"),
      // Class overrides: the 2-level render() chain, both init chains, the property
      // override (property + getter + setter accessor edges).
      (Family.hierCorePath, hierCore, Family.squareRender, Family.baseWidgetRender, "override func render()"),
      (Family.hierCorePath, hierCore, Family.roundedSquareRender, Family.squareRender, "override func render()"),
      (Family.hierCorePath, hierCore, Family.squareInit, Family.baseWidgetInit, "override init()"),
      (Family.hierCorePath, hierCore, Family.roundedSquareInit, Family.squareInit, "class RoundedSquare: Square"),
      (Family.hierCorePath, hierCore, Family.squareFrame, Family.baseWidgetFrame, "override var frame"),
      (Family.hierCorePath, hierCore, Family.squareFrameGetter, Family.baseWidgetFrameGetter, "\"square\""),
      (Family.hierCorePath, hierCore, Family.squareFrameSetter, Family.baseWidgetFrameSetter, "set {}"),
      // Cross-module retroactive conformance to a LOCAL-package protocol — the D-23
      // carrier: witness edges already ride the extension's document today.
      (Family.hierExtPath, hierExt, Family.wheelGlow, Family.glowableGlow, "func glow()"),
      // External-protocol witnesses (04-02, D-22): targets render in the frozen
      // Swift-module form — `scip-swift swift Swift <pin> …` — with system-ness from
      // the USR parse, never the use-site location (RESEARCH Q4).
      (Family.hierCorePath, hierCore, Family.rectDescription, Family.csdDescription, "var description: String"),
      (Family.hierCorePath, hierCore, Family.rectEquals, Family.equatableEquals, "static func == (lhs: Rect, rhs: Rect)"),
      // The retroactive external witness rides the extension document (D-23).
      (Family.hierExtPath, hierExt, Family.circleDescriptionExt, Family.csdDescription, "public var description"),
      // The ObjC-rooted subclass's inherited init: the store records it as a
      // definition at the decl line with an overrideOf edge to the never-minted
      // c:objc NSObject init (04-01 finding; 04-02 minting makes it lint-safe).
      (Family.hierCorePath, hierCore, Family.objcAnimalInit, Family.nsObjectInitTerm, "class ObjCAnimal: NSObject"),
    ]
    #expect(inventory.count == 23, "the witness inventory enumerates every expected edge")

    var expected = Set<EdgeKey>()
    for row in inventory {
      // Structural grounding: the subject has exactly ONE definition occurrence in its
      // document, and the fixture source at that line carries the declared shape.
      let definitions = index.allOccurrences.filter {
        $0.relativePath == row.path && $0.symbol == row.symbol
          && $0.symbolRoles & Roles.definitionBit != 0
      }
      #expect(
        definitions.count == 1,
        "\(row.symbol) must have exactly one definition occurrence in \(row.path), found \(definitions.count)"
      )
      if let definition = definitions.first {
        let line = Int(definition.line)
        #expect(
          row.fixture.lines.indices.contains(line)
            && row.fixture.lines[line].contains(row.lineFragment),
          "\(row.symbol) is defined at \(row.path):\(line), which must contain '\(row.lineFragment)'"
        )
      }
      expected.insert(
        EdgeKey(
          relativePath: row.path, symbol: row.symbol, target: row.target,
          isReference: true, isImplementation: true))
    }
    #expect(expected.count == 23, "the twenty-three witness edges must be distinct")

    // The type-level clause edges are part of the same corpus (04-02): the corpus-wide
    // both-direction sweep below must account for them too.
    expected.formUnion(try Self.expectedTypeLevelEdges(hierCore: hierCore, hierExt: hierExt))

    // Both directions over the WHOLE corpus: every expected edge IS emitted, every
    // emitted edge IS expected — no unexpected edges anywhere.
    let actual = Set(index.edges.map(EdgeKey.init))
    let missing = expected.subtracting(actual).sorted().prefix(5)
    #expect(
      missing.isEmpty,
      "missing witness edges: \(missing) — the `.overrideOf` mapping contract broke"
    )
    let unexpected = actual.subtracting(expected).sorted().prefix(5)
    #expect(
      unexpected.isEmpty,
      "unexpected relationship edges: \(unexpected) — emission drifted from the frozen baseline"
    )
  }

  @Test("implicit default-implementation occurrences contribute no relationship")
  func implicitDefaultImplementationOccurrencesAreNonEdges() throws {
    let index = try Self.sharedIndex()
    let hierCore = try Self.hierCoreFixture()

    // RESEARCH pitfall 2: every conforming type that relies on the default
    // implementation records an IMPLICIT occurrence of the default-impl symbol at its
    // conformance-declaration line. Those occurrences exist in the corpus (proven
    // below) but carry no definition bit, so the def-gated emission site attaches no
    // relationship to them — a rule reading relations off non-def occurrences would
    // synthesize phantom edges.
    let conformanceDeclAnchors = [
      "public struct Circle: HierShape {",
      "struct Rect: HierShape, Equatable, CustomStringConvertible {",
      "struct 🎨: HierShape {",
      "extension Wheel: HierShape {",
      "extension Wrapper: HierShape, HierDrawable where T: HierShape {",
    ]
    for anchor in conformanceDeclAnchors {
      let line = try Self.uniqueLine(in: hierCore, containing: anchor)
      let implicitOccurrences = index.occurrences(in: Family.hierCorePath, atLine: line)
        .filter { $0.symbol == Family.defaultImplTerm }
      #expect(
        !implicitOccurrences.isEmpty,
        "the implicit default-impl occurrence must exist at \(Family.hierCorePath):\(line) ('\(anchor)')"
      )
      #expect(
        implicitOccurrences.allSatisfy { $0.symbolRoles & Roles.definitionBit == 0 },
        "implicit default-impl occurrences must not carry the definition bit"
      )
    }

    // The ONLY relationship with the default-impl symbol as subject is the single
    // default-implementation witness edge, whose subject definition is the extension
    // method itself — the five implicit sites contribute nothing.
    let defaultImplEdges = index.edges.filter { $0.symbol == Family.defaultImplTerm }
    #expect(defaultImplEdges.count == 1, "exactly one default-impl witness edge")
    #expect(
      defaultImplEdges.first?.target == Family.hierShapeDescribe,
      "the default-impl witness targets the protocol requirement"
    )
  }

  @Test("every declared clause carries its type-level is_implementation edge (04-02)")
  func declaredClausesCarryTypeLevelEdges() throws {
    let index = try Self.sharedIndex()
    let hierCore = try Self.hierCoreFixture()
    let hierExt = try Self.hierExtFixture()
    let expected = try Self.expectedTypeLevelEdges(hierCore: hierCore, hierExt: hierExt)

    // Direction A: every declared clause's type-level edge IS emitted.
    let actual = Set(index.edges.map(EdgeKey.init))
    let missing = expected.subtracting(actual).sorted()
    #expect(
      missing.isEmpty,
      "missing type-level clause edges: \(missing) — the clause-relation harvest broke"
    )

    // Direction B: every type-level edge maps to a declared clause. The family is
    // identified structurally (the subject set of the clause inventory); an edge from
    // any clause subject to an undeclared target fails here.
    let clauseSubjects = Set(Self.clauseInventory(hierCore: hierCore, hierExt: hierExt).map(\.symbol))
    let actualTypeLevel = actual.filter { clauseSubjects.contains($0.symbol) }
    let unexpected = actualTypeLevel.subtracting(expected).sorted()
    #expect(
      unexpected.isEmpty,
      "unexpected type-level relationship edges: \(unexpected) — a conformance was invented"
    )

    // Attachment (D-23): in-decl edges ride the type's OWN SymbolInformation in its
    // defining document; extension-declared edges ride the EXTENSION document via the
    // carrier SymbolInformation for the type's canonical string — never an `s:e:`
    // extension-symbol Term subject (RESEARCH pitfall 3).
    for row in Self.clauseInventory(hierCore: hierCore, hierExt: hierExt) {
      let carrier = index.documentSymbols[row.path]?
        .first { $0.symbol == row.symbol }
      #expect(
        carrier != nil,
        "\(row.symbol) must have a SymbolInformation in \(row.path) (definition or D-23 carrier)"
      )
      if let carrier {
        #expect(
          carrier.relationships.contains { relationship in
            relationship.symbol == row.target
              && relationship.isImplementation && !relationship.isReference
          },
          "\(row.symbol) in \(row.path) must carry the type-level edge to \(row.target) with isImplementation only"
        )
      }
    }
  }

  // MARK: - Type-level clause inventory (04-02)

  /// One declared conformance/inheritance clause of the fixture: the type-level edge's
  /// (document, subject, target) plus the fragment that must appear on the source line
  /// where the clause is declared. Subjects are canonical TYPE strings — never `s:e:`
  /// extension-symbol Terms (pitfall 3).
  private struct ClauseRow {
    let path: String
    let fixture: Fixture
    let symbol: String
    let target: String
    let lineFragment: String
  }

  /// The declared-clause inventory: every conformance/inheritance clause of the fixture,
  /// one row per (subject, target) edge — direct conformances (Circle, Rect incl. its
  /// two external protocols, 🎨), extension-declared (Wheel: HierShape same-module,
  /// Wheel: Glowable + Circle: CustomStringConvertible retroactive cross-module — the
  /// D-23 carrier rows), the conditional conformance (Wrapper, one edge per protocol),
  /// the class chain (Square, RoundedSquare), protocol inheritance (HierShape), and the
  /// ObjC-rooted superclass whose store gap the D-21 SwiftSyntax fallback fills
  /// (ObjCAnimal → NSObject, c:objc fallback-Term target pinned as-is).
  private static let clauseInventoryShape: [(path: String, symbol: String, target: String, lineFragment: String)] = [
    (Family.hierCorePath, Family.circleType, Family.hierShapeType, "public struct Circle: HierShape {"),
    (Family.hierCorePath, Family.rectType, Family.hierShapeType, "struct Rect: HierShape, Equatable"),
    (Family.hierCorePath, Family.rectType, Family.equatableType, "struct Rect: HierShape, Equatable"),
    (Family.hierCorePath, Family.rectType, Family.csdType, "struct Rect: HierShape, Equatable"),
    (Family.hierCorePath, Family.paletteType, Family.hierShapeType, "struct 🎨: HierShape {"),
    (Family.hierCorePath, Family.wheelType, Family.hierShapeType, "extension Wheel: HierShape {"),
    (Family.hierCorePath, Family.wrapperType, Family.hierShapeType, "extension Wrapper: HierShape, HierDrawable where"),
    (Family.hierCorePath, Family.wrapperType, Family.hierDrawableType, "extension Wrapper: HierShape, HierDrawable where"),
    (Family.hierCorePath, Family.squareType, Family.baseWidgetType, "class Square: BaseWidget {"),
    (Family.hierCorePath, Family.roundedSquareType, Family.squareType, "class RoundedSquare: Square {"),
    (Family.hierCorePath, Family.hierShapeType, Family.hierDrawableType, "protocol HierShape: HierDrawable {"),
    (Family.hierExtPath, Family.wheelType, Family.glowableType, "extension Wheel: Glowable {"),
    (Family.hierExtPath, Family.circleType, Family.csdType, "extension Circle: CustomStringConvertible {"),
    (Family.hierCorePath, Family.objcAnimal, Family.nsObjectTypeTerm, "class ObjCAnimal: NSObject"),
  ]

  private static func clauseInventory(hierCore: Fixture, hierExt: Fixture) -> [ClauseRow] {
    clauseInventoryShape.map { row in
      ClauseRow(
        path: row.path,
        fixture: row.path == Family.hierExtPath ? hierExt : hierCore,
        symbol: row.symbol,
        target: row.target,
        lineFragment: row.lineFragment)
    }
  }

  /// The expected type-level edge set, structurally grounded: the clause's source line
  /// must exist and carry the declared shape (one unique line per fragment).
  private static func expectedTypeLevelEdges(hierCore: Fixture, hierExt: Fixture) throws -> Set<EdgeKey> {
    var expected = Set<EdgeKey>()
    for row in clauseInventory(hierCore: hierCore, hierExt: hierExt) {
      _ = try uniqueLine(in: row.fixture, containing: row.lineFragment)
      expected.insert(
        EdgeKey(
          relativePath: row.path, symbol: row.symbol, target: row.target,
          isReference: false, isImplementation: true))
    }
    return expected
  }

  @Test("corpus relationship invariants: flags, ordering, one row per pair")
  func corpusRelationshipInvariantsHold() throws {
    let index = try Self.sharedIndex()

    // Every emitted relationship is an implementation edge in exactly one of two shapes
    // (04-02): witness edges carry isReference+isImplementation (the byte-stable
    // `.overrideOf` mapping), type-level clause edges carry isImplementation ONLY
    // (scip.proto:477-500 — Dog# has is_implementation with Animal# but NOT
    // is_reference). The other two proto flags stay unused (no flag abuse —
    // Scip_Relationship flags are Bool fields, asserted directly, never bit math).
    for edge in index.edges {
      #expect(edge.isImplementation, "\(edge.symbol) → \(edge.target) must set isImplementation")
      #expect(
        edge.isReference || (!edge.isTypeDefinition && !edge.isDefinition),
        "\(edge.symbol) → \(edge.target) is a type-level edge: reference/typeDefinition/definition must all stay false"
      )
      #expect(
        !edge.isTypeDefinition && !edge.isDefinition,
        "\(edge.symbol) → \(edge.target) must not set isTypeDefinition/isDefinition"
      )
    }

    // D-10 / RESEARCH pitfall 4: per-symbol relationship lists ascend by target symbol
    // string with exactly one row per (symbol, target) — the ported CanonicalizeRelationships
    // contract (Go canonicalize.go: SortRelationships over FlattenRelationships).
    for (path, symbols) in index.documentSymbols {
      for symbolInformation in symbols where !symbolInformation.relationships.isEmpty {
        let targets = symbolInformation.relationships.map(\.symbol)
        #expect(
          targets == targets.sorted(),
          "\(path) :: \(symbolInformation.symbol) relationships must ascend by target: \(targets)"
        )
        #expect(
          Set(targets).count == targets.count,
          "\(path) :: \(symbolInformation.symbol) has duplicate-target relationships: \(targets)"
        )
      }
    }
  }

  @Test("relationship-table.json matches the built index for every emitted edge (D-24)")
  func relationshipTableMatchesBuiltIndex() throws {
    let index = try Self.sharedIndex()

    // One row per emitted edge — the hand-reviewable golden. Deterministic: sorted by
    // relativePath, symbol, target.
    let rows = index.edges.map { RelationshipTableRow($0) }.sorted()

    let tablePath = (Self.fixtureRepoPath() as NSString)
      .appendingPathComponent("relationship-table.json")

    if ProcessInfo.processInfo.environment["UPDATE_RELATIONSHIP_TABLE"] == "1" {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(rows).write(to: URL(fileURLWithPath: tablePath))
      return
    }

    guard let committed = try? Data(contentsOf: URL(fileURLWithPath: tablePath)) else {
      Issue.record(
        "missing \(tablePath) — run UPDATE_RELATIONSHIP_TABLE=1 swift test --filter RelationshipParity to generate it"
      )
      return
    }
    let committedRows = try JSONDecoder().decode([RelationshipTableRow].self, from: committed)

    // D-24 sanity gates before comparing: non-empty, carries the is_implementation
    // family (trivially true for the witness baseline — pinned anyway so a future
    // mixed-flag corpus can't vacuously pass), carries the retroactive-to-local row,
    // and stays within a band of the clause+witness count.
    #expect(!committedRows.isEmpty, "the committed relationship table must not be empty")
    #expect(
      committedRows.contains { $0.isImplementation },
      "the table must contain at least one is_implementation row"
    )
    #expect(
      committedRows.contains {
        $0.relativePath == Family.hierExtPath && $0.symbol == Family.wheelGlow
      },
      "the table must contain the retroactive-to-local witness row (D-23 carrier)"
    )
    #expect(
      committedRows.count >= 30 && committedRows.count <= 45,
      "table row count \(committedRows.count) is outside the clause+witness band [30, 45]"
    )

    // Both directions: the built rows equal the committed rows.
    if Set(committedRows) != Set(rows) {
      let committedSet = Set(committedRows)
      let rowSet = Set(rows)
      let missing = rowSet.subtracting(committedSet).sorted().prefix(5)
      let stale = committedSet.subtracting(rowSet).sorted().prefix(5)
      Issue.record(
        "relationship-table.json is stale — regenerate with UPDATE_RELATIONSHIP_TABLE=1 under the pinned toolchain if the change is intentional. New/changed: \(missing); removed: \(stale)"
      )
    }
  }

  // MARK: - Built-index plumbing

  /// One flattened relationship edge: the subject's document, the subject symbol
  /// string, the relationship target, and the four proto flags. The comparison unit
  /// for every both-direction sweep in this suite.
  private struct RelationshipEdge: Hashable {
    let relativePath: String
    let symbol: String
    let target: String
    let isReference: Bool
    let isImplementation: Bool
    let isTypeDefinition: Bool
    let isDefinition: Bool

    init(
      relativePath: String, symbol: String, relationship: Scip_Relationship
    ) {
      self.relativePath = relativePath
      self.symbol = symbol
      self.target = relationship.symbol
      self.isReference = relationship.isReference
      self.isImplementation = relationship.isImplementation
      self.isTypeDefinition = relationship.isTypeDefinition
      self.isDefinition = relationship.isDefinition
    }
  }

  /// Set-key identity of one edge: (document, symbol, target) with the flags — a
  /// different flag assignment on the same pair is a different (wrong) edge.
  private struct EdgeKey: Hashable, Comparable {
    let relativePath: String
    let symbol: String
    let target: String
    let isReference: Bool
    let isImplementation: Bool

    init(_ edge: RelationshipEdge) {
      self.relativePath = edge.relativePath
      self.symbol = edge.symbol
      self.target = edge.target
      self.isReference = edge.isReference
      self.isImplementation = edge.isImplementation
    }

    init(
      relativePath: String, symbol: String, target: String,
      isReference: Bool, isImplementation: Bool
    ) {
      self.relativePath = relativePath
      self.symbol = symbol
      self.target = target
      self.isReference = isReference
      self.isImplementation = isImplementation
    }

    static func < (lhs: EdgeKey, rhs: EdgeKey) -> Bool {
      if lhs.relativePath != rhs.relativePath { return lhs.relativePath < rhs.relativePath }
      if lhs.symbol != rhs.symbol { return lhs.symbol < rhs.symbol }
      return lhs.target < rhs.target
    }
  }

  /// One flattened occurrence with its document path and 0-based line attached (the
  /// NON-edge pins assert implicit occurrences exist at specific source lines).
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
    let edges: [RelationshipEdge]
    let allOccurrences: [FlatOccurrence]
    let documentSymbols: [String: [Scip_SymbolInformation]]

    init(_ index: Scip_Index) {
      var edges: [RelationshipEdge] = []
      var flat: [FlatOccurrence] = []
      var documentSymbols: [String: [Scip_SymbolInformation]] = [:]
      for document in index.documents {
        documentSymbols[document.relativePath] = document.symbols
        for symbol in document.symbols {
          for relationship in symbol.relationships {
            edges.append(
              RelationshipEdge(
                relativePath: document.relativePath,
                symbol: symbol.symbol,
                relationship: relationship))
          }
        }
        for occurrence in document.occurrences {
          flat.append(FlatOccurrence(relativePath: document.relativePath, occurrence: occurrence))
        }
      }
      self.edges = edges
      self.allOccurrences = flat
      self.documentSymbols = documentSymbols
    }

    /// The SymbolInformation for one canonical symbol string in one document, when the
    /// corpus defines it there.
    func symbolInformation(
      in relativePath: String, symbol: String
    ) -> Scip_SymbolInformation? {
      documentSymbols[relativePath]?.first { $0.symbol == symbol }
    }

    func occurrences(in relativePath: String, atLine line: Int32) -> [FlatOccurrence] {
      allOccurrences.filter {
        $0.relativePath == relativePath && $0.line == line
      }
    }
  }

  /// The built index is cached per test run: every test in this suite asserts over the
  /// same corpus, and one fixture build (a real `swift build`) is enough.
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
      let built = BuiltIndex(try RelationshipParityTests.buildFixtureIndex())
      cached = built
      return built
    }
  }

  /// Mirrors `ScipCLIGateTests.buildIndex` / `RoleParityTests.buildFixtureIndex` (both
  /// private there): SwiftPMBuildRunner produces the index store, `swift build
  /// --build-tests` folds any test targets into the same store (HierarchiesFixture has
  /// none — the flag is a no-op that keeps the scaffolding shape identical), then the
  /// in-process SCIPIndexBuilder emits the Scip_Index.
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

    // Compile test targets into the SAME index store (same scratch path) so any test
    // target category is indexed too. Fixed argument vector; failure is a fixture bug.
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
      .appendingPathComponent("Fixtures/HierarchiesFixture").path
  }

  private static func makeTemporaryDirectory() throws -> String {
    let path = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("scip-swift-relationship-parity-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }

  // MARK: - Fixture sources (structural line resolution — the source is the truth)

  private struct Fixture {
    let relativePath: String
    let lines: [String]
  }

  private static func hierCoreFixture() throws -> Fixture {
    try fixture("Sources/HierCore/HierCore.swift")
  }

  private static func hierExtFixture() throws -> Fixture {
    try fixture("Sources/HierExt/HierExt.swift")
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
      throw RelationshipParityAnchorError(
        anchor: anchor, file: fixture.relativePath, matchedLines: matches.map(\.offset))
    }
    return Int32(index)
  }

  private struct RelationshipParityAnchorError: Error, CustomStringConvertible {
    let anchor: String
    let file: String
    let matchedLines: [Int]
    var description: String {
      "fixture anchor '\(anchor)' in \(file) must match exactly one line, matched lines "
        + "\(matchedLines)"
    }
  }

  // MARK: - Pinned expectation families (exact canonical symbol strings)

  /// Exact canonical symbol strings for every relationship family the oracle pins.
  /// Hand-reviewable constants — the same strings the caret goldens and
  /// relationship-table.json carry.
  private enum Family {
    static let hierCorePath = "Sources/HierCore/HierCore.swift"
    static let hierExtPath = "Sources/HierExt/HierExt.swift"

    static let core = "scip-swift swiftpm HierCore . "
    static let ext = "scip-swift swiftpm HierExt . "

    // The 2-level render() override chain (Task 1 tracer family).
    static let baseWidgetRender = core + "BaseWidget#render()."
    static let squareRender = core + "Square#render()."
    static let roundedSquareRender = core + "RoundedSquare#render()."

    /// Every corpus symbol whose descriptor is `render().` — the structural family the
    /// tracer sweeps (a render override anywhere in the fixture lands here).
    static let renderFamilySubjects: Set<String> = [
      baseWidgetRender, squareRender, roundedSquareRender,
    ]

    // Local-protocol requirement targets (HierShape inherits HierDrawable's draw()).
    static let hierDrawableDraw = core + "HierDrawable#draw()."
    static let hierShapeArea = core + "HierShape#area."
    static let hierShapeDescribe = core + "HierShape#describe()."

    // Local-protocol witnesses — direct conformances.
    static let circleArea = core + "Circle#area."
    static let circleDraw = core + "Circle#draw()."
    static let rectArea = core + "Rect#area."
    static let rectDraw = core + "Rect#draw()."
    static let paletteArea = core + "`🎨`#area."
    static let paletteDraw = core + "`🎨`#draw()."

    // Local-protocol witnesses — extension-declared conformances.
    static let wheelArea = core + "Wheel#area."
    static let wheelDraw = core + "Wheel#draw()."
    static let wheelGlow = core + "Wheel#glow()."
    static let glowableGlow = ext + "Glowable#glow()."

    // Conditional-conformance witnesses and the default implementation: raw-USR
    // fallback Terms (protocol-extension and conformance-context manglings are
    // unparseable today — v1-documented, pinned as emitted).
    static let wrapperAreaTerm = core + "`s:8HierCore7WrapperVA2A0A5ShapeRzlE4areaSdvp`."
    static let wrapperDrawTerm = core + "`s:8HierCore7WrapperVA2A0A5ShapeRzlE4drawyyF`."
    static let defaultImplTerm = core + "`s:8HierCore0A5ShapePAAE8describeSSyF`."

    // Class-override family: init chains and the overridden property (property,
    // getter, and setter each emit their own edge).
    static let baseWidgetInit = core + "BaseWidget#init()."
    static let squareInit = core + "Square#init()."
    static let roundedSquareInit = core + "RoundedSquare#init()."
    static let baseWidgetFrame = core + "BaseWidget#frame."
    static let baseWidgetFrameGetter = core + "BaseWidget#frame()."
    static let baseWidgetFrameSetter = core + "BaseWidget#`frame=`()."
    static let squareFrame = core + "Square#frame."
    static let squareFrameGetter = core + "Square#frame()."
    static let squareFrameSetter = core + "Square#`frame=`()."

    // External-protocol targets (04-02, D-22): the frozen Swift-module form. The
    // pinned toolchain version is the same constant the mapper uses — these strings
    // are what the parser rules must produce.
    static let swiftSystem = "scip-swift swift Swift \(ToolchainInfo.pinnedSwiftVersion) "
    static let equatableType = swiftSystem + "Equatable#"
    static let equatableEquals = swiftSystem + "Equatable#`==`()."
    static let csdType = swiftSystem + "CustomStringConvertible#"
    static let csdDescription = swiftSystem + "CustomStringConvertible#description."

    // External-protocol witnesses (04-02).
    static let rectDescription = core + "Rect#description."
    static let rectEquals = core + "Rect#`==`()."
    static let circleDescriptionExt = core + "Circle#description."

    // The ObjC-rooted subclass: @objc-exposed members ride pseudo-module USRs
    // (`c:@M@HierCore@objc(cs)ObjCAnimal(im)init` — the module-import parse path names
    // them verbatim), the inherited init's never-occurring target is a c:objc fallback
    // Term (04-01 finding), and the D-21 fallback's superclass edge targets the
    // NSObject type's c:objc fallback Term — all pinned as-is (v1).
    static let objcAnimalInit =
      "scip-swift swiftpm HierCore@objc(cs)ObjCAnimal(im)init . init()."
    static let objcAnimalType =
      "scip-swift swiftpm HierCore@objc(cs)ObjCAnimal . `HierCore@objc(cs)ObjCAnimal`#"
    static let nsObjectInitTerm = core + "`c:objc(cs)NSObject(im)init`."
    static let nsObjectTypeTerm = core + "`c:objc(cs)NSObject`."

    // Type-level clause subjects and local targets (04-02).
    static let circleType = core + "Circle#"
    static let rectType = core + "Rect#"
    static let paletteType = core + "`🎨`#"
    static let wheelType = core + "Wheel#"
    static let wrapperType = core + "Wrapper#"
    static let squareType = core + "Square#"
    static let roundedSquareType = core + "RoundedSquare#"
    static let hierShapeType = core + "HierShape#"
    static let hierDrawableType = core + "HierDrawable#"
    static let baseWidgetType = core + "BaseWidget#"
    static let objcAnimal = objcAnimalType
    static let glowableType = ext + "Glowable#"
  }

  // MARK: - Role bits (Scip_SymbolRole raw values — Generated/Scip.pb.swift).

  private enum Roles {
    static let definitionBit: Int32 = Int32(Scip_SymbolRole.definition.rawValue)
  }

  // MARK: - Row identity

  /// One row of the committed relationship-expectation table (D-24): a (document,
  /// subject, target, isReference, isImplementation) edge. Codable field names are the
  /// stable contract of the golden file.
  private struct RelationshipTableRow: Codable, Equatable, Hashable, Comparable {
    let relativePath: String
    let symbol: String
    let target: String
    let isReference: Bool
    let isImplementation: Bool

    init(_ edge: RelationshipEdge) {
      self.relativePath = edge.relativePath
      self.symbol = edge.symbol
      self.target = edge.target
      self.isReference = edge.isReference
      self.isImplementation = edge.isImplementation
    }

    static func < (lhs: RelationshipTableRow, rhs: RelationshipTableRow) -> Bool {
      if lhs.relativePath != rhs.relativePath { return lhs.relativePath < rhs.relativePath }
      if lhs.symbol != rhs.symbol { return lhs.symbol < rhs.symbol }
      return lhs.target < rhs.target
    }
  }
}
