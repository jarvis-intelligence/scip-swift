import Foundation
import Testing

@testable import scip_swift

/// Requirement: REL-03 / SC3 (04-03) — the type-hierarchy answerability oracle.
///
/// Proves that supertypes, subtypes, and protocol implementations are answerable
/// from the emitted index by CONSUMER-SIDE QUERY, exactly as scip.proto documents
/// the semantics (scip.proto:477-500, the Dog/Animal example: `Dog#` carries
/// `relationships = [{symbol: "Animal#", is_implementation: true}]` with NO
/// is_reference, and "Find implementations" on `Animal#` returns `Dog#`):
///
/// - **Forward query.** supertypes(T) = the union of `is_implementation`
///   relationship targets over EVERY SymbolInformation whose symbol is T —
///   across all documents AND `external_symbols`. Types whose conformances are
///   declared in extensions resolve through the TYPE's canonical string
///   regardless of which document carries the edge (D-23: the retroactive edge
///   rides the extension document via a carrier SymbolInformation FOR THE TYPE,
///   never an `s:e:` extension-symbol Term — so the string-keyed query finds it).
/// - **Reverse query.** implementations(T) / subtypes(T) = the reverse scan:
///   every SymbolInformation across all documents plus externalSymbols whose
///   relationships point at T. Implementations of Swift stdlib protocols are
///   first-class answers (D-22 — `Rect#: Equatable#`, `Circle#:
///   CustomStringConvertible#` in the frozen `scip-swift swift Swift <pin>` form).
///
/// Both directions are asserted exhaustively: every emitted `is_implementation`
/// edge is answerable forward (on its subject) and reverse (on its target), and
/// every query result maps back to a real edge — no orphan edges, no phantom
/// results. The type-level expectations reconcile with the committed
/// `relationship-table.json` golden the RelationshipParity oracle pins (the
/// isReference=false rows are exactly the type-level clause edges).
@Suite("TypeHierarchyAnswerability")
struct TypeHierarchyAnswerabilityTests {

  // MARK: - Test 1: forward supertypes for every fixture type

  @Test("supertypes(T): every fixture type's is_implementation targets match the declared clauses")
  func forwardSupertypesMatchDeclaredClauses() throws {
    let index = try Self.sharedIndex()
    let hierCore = try Self.hierCoreFixture()
    let hierExt = try Self.hierExtFixture()

    // One row per fixture TYPE: its expected supertype set (source-declared
    // clauses only — availability of a default implementation is not a clause)
    // and the fragments that must appear on each clause's source line.
    // struct/class/protocol types; the ObjC-rooted subclass's superclass edge
    // targets the pinned c:objc fallback Term (v1, as-is).
    let inventory: [(symbol: String, supertypes: Set<String>, clauses: [(fixture: Fixture, fragment: String)])] = [
      (Family.circleType, [Family.hierShapeType, Family.csdType], [
        (hierCore, "public struct Circle: HierShape {"),
        (hierExt, "extension Circle: CustomStringConvertible {"),
      ]),
      (Family.rectType, [Family.hierShapeType, Family.equatableType, Family.csdType], [
        (hierCore, "struct Rect: HierShape, Equatable, CustomStringConvertible {"),
      ]),
      (Family.paletteType, [Family.hierShapeType], [
        (hierCore, "struct 🎨: HierShape {"),
      ]),
      (Family.wheelType, [Family.hierShapeType, Family.glowableType], [
        (hierCore, "extension Wheel: HierShape {"),
        (hierExt, "extension Wheel: Glowable {"),
      ]),
      (Family.wrapperType, [Family.hierShapeType, Family.hierDrawableType], [
        (hierCore, "extension Wrapper: HierShape, HierDrawable where T: HierShape {"),
      ]),
      (Family.squareType, [Family.baseWidgetType], [
        (hierCore, "class Square: BaseWidget {"),
      ]),
      (Family.roundedSquareType, [Family.squareType], [
        (hierCore, "class RoundedSquare: Square {"),
      ]),
      (Family.hierShapeType, [Family.hierDrawableType], [
        (hierCore, "protocol HierShape: HierDrawable {"),
      ]),
      // Root types with no declared supertypes — the forward query must answer
      // the empty set, not miss.
      (Family.hierDrawableType, [], []),
      (Family.baseWidgetType, [], []),
      (Family.glowableType, [], []),
      (Family.objcAnimalType, [Family.nsObjectTypeTerm], [
        (hierCore, "class ObjCAnimal: NSObject {"),
      ]),
    ]

    for row in inventory {
      // Grounding: every declared clause exists as a unique source line.
      for clause in row.clauses {
        _ = try Self.uniqueLine(in: clause.fixture, containing: clause.fragment)
      }

      let actual = index.supertypes(of: row.symbol)
      #expect(
        actual == row.supertypes,
        "supertypes(\(row.symbol)) must be \(row.supertypes.sorted()), got \(actual.sorted())"
      )
    }
  }

  // MARK: - Test 2: reverse subtypes/implementations

  @Test("implementations(T)/subtypes(T): the reverse scan over documents + externalSymbols")
  func reverseImplementationsMatchSourceInventory() throws {
    let index = try Self.sharedIndex()

    // The reverse inventory, derived from the fixture source: every protocol/
    // class that something conforms to or inherits from, with its expected
    // implementor/subtype set. Wheel arrives through BOTH extension documents
    // (same-module HierCore + retroactive HierExt); Circle's CustomStringConvertible
    // conformance arrives through the extension-document carrier (D-23).
    let inventory: [(target: String, expected: Set<String>, what: String)] = [
      (Family.hierDrawableType, [Family.hierShapeType, Family.wrapperType], "protocol inheritance + conditional conformance"),
      (
        Family.hierShapeType,
        [Family.circleType, Family.rectType, Family.paletteType, Family.wheelType, Family.wrapperType],
        "all five conforming types incl. extension-declared (Wheel) and conditional (Wrapper)"
      ),
      (Family.equatableType, [Family.rectType], "external Swift protocol (D-22)"),
      (Family.csdType, [Family.rectType, Family.circleType], "external Swift protocol incl. the D-23 carrier (Circle)"),
      (Family.squareType, [Family.roundedSquareType], "class subtypes (chain level 2)"),
      (Family.baseWidgetType, [Family.squareType], "class subtypes (chain level 1)"),
      (Family.glowableType, [Family.wheelType], "cross-module retroactive-to-local protocol"),
      (Family.nsObjectTypeTerm, [Family.objcAnimalType], "the ObjC-rooted superclass (fallback-Term target, v1)"),
    ]

    for row in inventory {
      let actual = index.implementations(of: row.target)
      #expect(
        actual == row.expected,
        "implementations(\(row.target)) [\(row.what)] must be \(row.expected.sorted()), got \(actual.sorted())"
      )
    }

    // The scan is same-package AND external: stdlib protocol implementors are
    // first-class answers (D-22 — a hierarchy that quietly omits Equatable
    // conformers is the narrowing the phase rejects). The reverse scan also
    // covers externalSymbols' relationships (the query iterates documents AND
    // externalSymbols); on this corpus no external symbol carries one — pinned
    // here so a future externally-carried edge cannot silently bypass the scan:
    // it would land in this list and flow through the same query path.
    #expect(
      index.externalSymbolRelationships.isEmpty,
      "no external symbol carries a relationship on this corpus (v1 shape) — found \(index.externalSymbolRelationships.count)"
    )
  }

  // MARK: - Test 3: exhaustive both-direction invariant

  @Test("every is_implementation edge answers forward and reverse; no phantom results")
  func forwardReverseMutualInverseHolds() throws {
    let index = try Self.sharedIndex()
    let implementationEdges = index.edges.filter { $0.relationship.isImplementation }

    #expect(
      !implementationEdges.isEmpty,
      "the corpus must carry is_implementation edges"
    )
    // Forward: every edge's target IS in supertypes(subject) — witness edges on
    // member symbols included (the query is symbol-keyed, so members answer the
    // same forward query a type does). Reverse: every edge's subject IS in
    // implementations(target).
    for edge in implementationEdges {
      #expect(
        index.supertypes(of: edge.symbol).contains(edge.relationship.symbol),
        "\(edge.symbol) → \(edge.relationship.symbol) must be forward-answerable (supertypes contains the target)"
      )
      #expect(
        index.implementations(of: edge.relationship.symbol).contains(edge.symbol),
        "\(edge.symbol) → \(edge.relationship.symbol) must be reverse-answerable (implementations contains the subject)"
      )
    }

    // No phantoms, in both directions, for EVERY symbol of the corpus: the query
    // result equals exactly the edge-derived set.
    let everySymbol = Set(index.edges.flatMap { [$0.symbol, $0.relationship.symbol] })
    for symbol in everySymbol {
      let forwardDerived = Set(
        implementationEdges
          .filter { $0.symbol == symbol }
          .map(\.relationship.symbol))
      #expect(
        index.supertypes(of: symbol) == forwardDerived,
        "supertypes(\(symbol)) must equal its edge-derived target set — got \(index.supertypes(of: symbol).sorted()), edges give \(forwardDerived.sorted())"
      )

      let reverseDerived = Set(
        implementationEdges
        .filter { $0.relationship.symbol == symbol }
        .map(\.symbol))
      #expect(
        index.implementations(of: symbol) == reverseDerived,
        "implementations(\(symbol)) must equal its edge-derived subject set — got \(index.implementations(of: symbol).sorted()), edges give \(reverseDerived.sorted())"
      )
    }
  }

  // MARK: - Test 4: extension-declared resolution via the TYPE's string (D-23)

  @Test("extension-declared conformances answer via the TYPE's canonical string (D-23)")
  func extensionDeclaredConformancesResolveViaTypeString() throws {
    let index = try Self.sharedIndex()
    let hierCore = try Self.hierCoreFixture()
    let hierExt = try Self.hierExtFixture()

    // SC3's extension clause: Wheel's and Circle's conformances live in
    // extension documents, but the queries resolve through the TYPE's canonical
    // string — the answerability contract D-23 pins.
    #expect(
      index.supertypes(of: Family.wheelType) == [Family.hierShapeType, Family.glowableType],
      "Wheel answers via its own string — same-module extension (HierShape) and cross-module retroactive (Glowable)"
    )
    #expect(
      index.supertypes(of: Family.circleType) == [Family.hierShapeType, Family.csdType],
      "Circle answers via its own string — in-decl (HierShape) and retroactive external (CustomStringConvertible)"
    )

    // The carrier mechanics (D-23): the extension documents carry a
    // SymbolInformation FOR THE TYPE's canonical string holding the edge — the
    // glow/description edges never ride an `s:e:` extension-symbol Term, and the
    // type's defining document is untouched by the retroactive edge.
    let extDocument = try #require(
      index.documentSymbols[Family.hierExtPath],
      "the HierExt document must exist"
    )
    let wheelCarrier = extDocument.first { $0.symbol == Family.wheelType }
    #expect(
      wheelCarrier?.relationships.contains {
        $0.symbol == Family.glowableType && $0.isImplementation
      } == true,
      "HierExt must carry Wheel#'s SymbolInformation with the Glowable edge (the D-23 carrier)"
    )
    let circleCarrier = extDocument.first { $0.symbol == Family.circleType }
    #expect(
      circleCarrier?.relationships.contains {
        $0.symbol == Family.csdType && $0.isImplementation
      } == true,
      "HierExt must carry Circle#'s SymbolInformation with the CustomStringConvertible edge (the D-23 carrier)"
    )

    // Grounding: the carriers sit at the extension clause lines.
    let wheelClause = try Self.uniqueLine(in: hierExt, containing: "extension Wheel: Glowable {")
    let circleClause = try Self.uniqueLine(in: hierExt, containing: "extension Circle: CustomStringConvertible {")
    for (symbol, clause) in [(Family.wheelType, wheelClause), (Family.circleType, circleClause)] {
      let carrierOccurrences = index.occurrences(
        in: Family.hierExtPath, symbol: symbol, atLine: clause)
      #expect(
        !carrierOccurrences.isEmpty,
        "\(symbol) must be occurrence-anchored in HierExt at the clause line \(clause)"
      )
    }

    // And the same-module extension conformance (Wheel: HierShape in HierCore)
    // resolves through the type string as well — its edge rides the HierCore
    // extension document, not Wheel's struct declaration.
    let wheelCoreClause = try Self.uniqueLine(in: hierCore, containing: "extension Wheel: HierShape {")
    let wheelCoreDocument = try #require(index.documentSymbols[Family.hierCorePath])
    let wheelCoreCarrier = wheelCoreDocument.first { $0.symbol == Family.wheelType }
    #expect(
      wheelCoreCarrier?.relationships.contains {
        $0.symbol == Family.hierShapeType && $0.isImplementation
      } == true,
      "HierCore must carry Wheel#'s SymbolInformation with the HierShape edge (same-module extension carrier)"
    )
    #expect(
      !index.occurrences(in: Family.hierCorePath, symbol: Family.wheelType, atLine: wheelCoreClause).isEmpty,
      "Wheel# must be occurrence-anchored in HierCore at the extension clause line \(wheelCoreClause)"
    )

    // Reconciliation (D-24 stack coherence): the type-level rows of the
    // committed relationship-table.json — the RelationshipParity golden over
    // the same fixture build — are exactly the type-level supertype pairs this
    // suite derives: every committed isReference=false row answers forward and
    // reverse here, and every derived type-level edge is a committed row.
    let tablePath = (Self.fixtureRepoPath() as NSString)
      .appendingPathComponent("relationship-table.json")
    let committed = try #require(
      try? Data(contentsOf: URL(fileURLWithPath: tablePath)),
      "missing \(tablePath) — the committed RelationshipParity golden"
    )
    let committedRows = try JSONDecoder().decode([RelationshipTableRow].self, from: committed)
    let committedTypeLevel = Set(
      committedRows
        .filter { !$0.isReference && $0.isImplementation }
        .map { "\(rowKey($0))" })
    let derivedTypeLevel = Set(
      index.edges
        .filter { !$0.relationship.isReference && $0.relationship.isImplementation }
        .map { "\(rowKey(RelationshipTableRow($0)))" })
    #expect(
      derivedTypeLevel == committedTypeLevel,
      "the derived type-level edges must equal the committed relationship table's isReference=false rows — derived \(derivedTypeLevel.sorted()), committed \(committedTypeLevel.sorted())"
    )
  }

  private func rowKey(_ row: RelationshipTableRow) -> String {
    "\(row.relativePath)|\(row.symbol)|\(row.target)"
  }

  // MARK: - Built-index plumbing

  /// One flattened relationship edge: subject document, subject symbol, target,
  /// flags — over documents AND externalSymbols.
  private struct RelationshipEdge {
    let relativePath: String
    let symbol: String
    let relationship: Scip_Relationship
  }

  private struct FlatOccurrence: Hashable {
    let relativePath: String
    let line: Int32
    let symbol: String
    let symbolRoles: Int32
  }

  /// The built index with the two consumer queries: the forward supertype read
  /// and the reverse implementations scan, both keyed by symbol string over the
  /// union of all documents' symbols and externalSymbols.
  private struct BuiltIndex {
    let documentSymbols: [String: [Scip_SymbolInformation]]
    let externalSymbols: [Scip_SymbolInformation]
    let edges: [RelationshipEdge]
    let occurrencesByDocument: [String: [FlatOccurrence]]

    init(_ index: Scip_Index) {
      var documentSymbols: [String: [Scip_SymbolInformation]] = [:]
      var edges: [RelationshipEdge] = []
      var occurrences: [String: [FlatOccurrence]] = [:]
      for document in index.documents {
        documentSymbols[document.relativePath] = document.symbols
        for info in document.symbols {
          for relationship in info.relationships {
            edges.append(
              RelationshipEdge(
                relativePath: document.relativePath,
                symbol: info.symbol,
                relationship: relationship))
          }
        }
        occurrences[document.relativePath] = document.occurrences.map {
          FlatOccurrence(
            relativePath: document.relativePath,
            line: $0.singleLineRange.line,
            symbol: $0.symbol,
            symbolRoles: $0.symbolRoles)
        }
      }
      var externalEdges: [RelationshipEdge] = []
      for info in index.externalSymbols {
        for relationship in info.relationships {
          externalEdges.append(
            RelationshipEdge(
              relativePath: "external_symbols",
              symbol: info.symbol,
              relationship: relationship))
        }
      }
      self.documentSymbols = documentSymbols
      self.externalSymbols = index.externalSymbols
      self.edges = edges + externalEdges
      self.externalSymbolRelationships = externalEdges
      self.occurrencesByDocument = occurrences
      self.allSymbolInformations =
        documentSymbols.values.flatMap { $0 } + index.externalSymbols
    }

    let externalSymbolRelationships: [RelationshipEdge]

    /// Every SymbolInformation of the corpus: all documents' symbols plus
    /// externalSymbols — the table both queries scan.
    private let allSymbolInformations: [Scip_SymbolInformation]

    /// The forward query: union of is_implementation targets over every
    /// SymbolInformation whose symbol equals `symbol` (documents + external).
    func supertypes(of symbol: String) -> Set<String> {
      var targets = Set<String>()
      for info in allSymbolInformations {
        guard info.symbol == symbol else { continue }
        for relationship in info.relationships where relationship.isImplementation {
          targets.insert(relationship.symbol)
        }
      }
      return targets
    }

    /// The reverse query: every SymbolInformation (documents + external) whose
    /// relationships point is_implementation at `target`.
    func implementations(of target: String) -> Set<String> {
      var subjects = Set<String>()
      for info in allSymbolInformations {
        for relationship in info.relationships
        where relationship.isImplementation && relationship.symbol == target {
          subjects.insert(info.symbol)
        }
      }
      return subjects
    }

    func occurrences(in relativePath: String, symbol: String, atLine line: Int32) -> [FlatOccurrence] {
      (occurrencesByDocument[relativePath] ?? []).filter {
        $0.symbol == symbol && $0.line == line
      }
    }
  }

  /// The built index is cached per test run: every test in this suite asserts over
  /// the same corpus, and one fixture build (a real `swift build`) is enough.
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
      let built = BuiltIndex(try TypeHierarchyAnswerabilityTests.buildFixtureIndex())
      cached = built
      return built
    }
  }

  /// Mirrors `RelationshipParityTests.buildFixtureIndex` (private there):
  /// SwiftPMBuildRunner produces the index store, `swift build --build-tests`
  /// folds any test targets into the same store (HierarchiesFixture has none —
  /// the flag is a no-op that keeps the scaffolding shape identical), then the
  /// in-process SCIPIndexBuilder emits the Scip_Index. Temp state defer-cleaned.
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
      .appendingPathComponent("Fixtures/HierarchiesFixture").path
  }

  private static func makeTemporaryDirectory() throws -> String {
    let path = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("scip-swift-type-hierarchy-\(UUID().uuidString)")
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
      throw TypeHierarchyAnchorError(
        anchor, "\(fixture.relativePath): anchor must match exactly one line, matched \(matches.map(\.offset))")
    }
    return Int32(index)
  }

  private struct TypeHierarchyAnchorError: Error, CustomStringConvertible {
    let anchor: String
    let detail: String
    init(_ anchor: String, _ detail: String) {
      self.anchor = anchor
      self.detail = detail
    }
    var description: String { "TypeHierarchy anchor '\(anchor)': \(detail)" }
  }

  // MARK: - Pinned symbol families (exact canonical strings)

  /// Exact canonical symbol strings — the same strings relationship-table.json
  /// and the caret goldens carry (RelationshipParity's constants, restated so
  /// this suite stays self-contained).
  private enum Family {
    static let hierCorePath = "Sources/HierCore/HierCore.swift"
    static let hierExtPath = "Sources/HierExt/HierExt.swift"

    static let core = "scip-swift swiftpm HierCore . "
    static let ext = "scip-swift swiftpm HierExt . "
    static let swiftSystem = "scip-swift swift Swift \(ToolchainInfo.pinnedSwiftVersion) "

    // Types.
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
    static let glowableType = ext + "Glowable#"

    // The ObjC-rooted subclass and its superclass target (both pinned as
    // emitted, v1 — pseudo-module USR and c:objc fallback Term).
    static let objcAnimalType =
      "scip-swift swiftpm HierCore@objc(cs)ObjCAnimal . `HierCore@objc(cs)ObjCAnimal`#"
    static let nsObjectTypeTerm = core + "`c:objc(cs)NSObject`."

    // External Swift protocols (D-22 frozen form).
    static let equatableType = swiftSystem + "Equatable#"
    static let csdType = swiftSystem + "CustomStringConvertible#"
  }

  // MARK: - Row identity

  /// One row of the committed relationship-expectation table (the RelationshipParity
  /// golden's stable field contract) — the reconciliation comparison unit.
  private struct RelationshipTableRow: Codable, Equatable, Hashable {
    let relativePath: String
    let symbol: String
    let target: String
    let isReference: Bool
    let isImplementation: Bool

    init(_ edge: RelationshipEdge) {
      self.relativePath = edge.relativePath
      self.symbol = edge.symbol
      self.target = edge.relationship.symbol
      self.isReference = edge.relationship.isReference
      self.isImplementation = edge.relationship.isImplementation
    }
  }
}
