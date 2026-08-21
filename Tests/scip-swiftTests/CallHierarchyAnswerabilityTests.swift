import Foundation
import Testing

@testable import scip_swift

/// Requirement: REL-02 / SC2 (04-03) — the call-hierarchy answerability oracle.
///
/// Proves that incoming and outgoing call sets are answerable for every function
/// and method of HierarchiesFixture by CONSUMER-SIDE DERIVATION over the emitted
/// index — the scip-java convention RESEARCH Q2 confirmed: scip.proto's
/// `SymbolRole` has exactly eight values (definition 1, import 2, writeAccess 4,
/// readAccess 8, generated 16, test 32, forwardDefinition 64 —
/// `Generated/Scip.pb.swift`; scip.proto:524-546) and NO `Call` bit, and
/// `Relationship` has only the four flags (is_reference, is_implementation,
/// is_type_definition, is_definition — scip.proto:465-517). There is no protocol
/// surface for synthesized call edges, and abusing the four flags as a call
/// channel would corrupt Find References for every consumer (plan prohibition).
/// Answerability therefore means: the emitted index carries every call site as
/// a reference occurrence with exact position and access bits, and a consumer
/// can derive the call graph from that data alone.
///
/// The derivation this suite simulates (test-local by design — `enclosing_symbol`
/// is locals-only by contract, `SCIPIndexBuilder.swift`'s locals branch, frozen):
///
/// 1. **Function family.** A symbol is function-family iff its SymbolInformation
///    kind (documents + external_symbols table) is constructor, function, getter,
///    method, or setter — this is what makes raw-USR fallback-Term functions
///    (conditional-conformance witnesses, the default implementation) visible to
///    the walk — OR its canonical string ends in `).` (a descriptor-carried
///    parameter list — minted external symbols such as `Swift String#init().`
///    carry kind=unspecified, so the descriptor supplies the family).
/// 2. **Attribution.** Per document, occurrences ordered by position; a
///    function-family occurrence carrying the Definition bit opens the current
///    function scope; a function-family occurrence without it that carries an
///    access bit (read or write — the emitted surface for a call site) is a
///    call site attributed to the nearest-preceding function definition.
///    Function-family occurrences with NO role bits are the implicit
///    availability rows (synthesized default-implementation occurrences at
///    conformance-declaration lines, RESEARCH pitfall 2, plus the ObjC
///    implicit-member flood): no consumer can read them as references, so the
///    derivation skips them — exactly like the def-gated relationship emission.
/// 3. **Direction.** outgoing(f) = callee symbols of f's attributed call sites;
///    incoming(g) = the reverse grouping.
///
/// Accepted v1 shapes the walk encodes (documented, never "fixed" here): the
/// `Double(spokes)` initializer call emits as an occurrence-only raw-USR fallback
/// Term (`s:SdySdSicfc`) that is function-family by neither kind nor descriptor,
/// so that one call is not answerable by name (v1 Term limitation, pinned in
/// 04-02); array-literal initializers emit the same way
/// (`s:Sa12arrayLiteralSayxGxd_tcfc`).
@Suite("CallHierarchyAnswerability")
struct CallHierarchyAnswerabilityTests {

  // MARK: - Task 1 (tracer): the cross-module chain, one function both directions

  @Test("tracer: outgoing(extCaller) == {coreDriver} and incoming(coreDriver) == {extCaller}")
  func crossModuleCallChainTracer() throws {
    let index = try Self.sharedIndex()
    let hierCore = try Self.hierCoreFixture()
    let hierExt = try Self.hierExtFixture()

    // Both function identities resolve structurally — never by magic line number
    // and never by a hand-typed symbol string: the definition occurrence on the
    // unique source line IS the emitted identity the derivation groups by.
    let extCallerLine = try Self.uniqueLine(
      in: hierExt, trimmedEquals: "func extCaller() {")
    let extCaller = try Self.functionDefinition(
      in: Family.hierExtPath, atLine: extCallerLine, index: index)

    let coreDriverLine = try Self.uniqueLine(
      in: hierCore, trimmedEquals: "public func coreDriver() {")
    let coreDriver = try Self.functionDefinition(
      in: Family.hierCorePath, atLine: coreDriverLine, index: index)

    let graph = Self.deriveCallGraph(index)

    // Outgoing: extCaller's body contains exactly the cross-module coreDriver() call.
    #expect(
      graph.outgoing[extCaller.symbol] == [coreDriver.symbol],
      "outgoing(extCaller) must be exactly {coreDriver} — got \(graph.outgoing[extCaller.symbol] ?? [])"
    )
    // Incoming: the reverse grouping over the same attribution.
    #expect(
      graph.incoming[coreDriver.symbol] == [extCaller.symbol],
      "incoming(coreDriver) must be exactly {extCaller} — got \(graph.incoming[coreDriver.symbol] ?? [])"
    )
  }

  @Test("tracer: chain call sites carry ReadAccess at exact positions (no Call bit exists)")
  func chainCallSitesCarryReadAccess() throws {
    let index = try Self.sharedIndex()
    let hierCore = try Self.hierCoreFixture()
    let hierExt = try Self.hierExtFixture()

    // scip.proto's SymbolRole has no Call bit (eight values — verified against
    // Generated/Scip.pb.swift raw values below); the emitted surface a consumer
    // actually has for a call site is the ReadAccess bit at the exact position.
    // Pin the enum surface this derivation relies on:
    #expect(Scip_SymbolRole.definition.rawValue == 1)
    #expect(Scip_SymbolRole.import.rawValue == 2)
    #expect(Scip_SymbolRole.writeAccess.rawValue == 4)
    #expect(Scip_SymbolRole.readAccess.rawValue == 8)
    #expect(Scip_SymbolRole.generated.rawValue == 16)
    #expect(Scip_SymbolRole.test.rawValue == 32)
    #expect(Scip_SymbolRole.forwardDefinition.rawValue == 64)

    let coreDriverLine = try Self.uniqueLine(
      in: hierCore, trimmedEquals: "public func coreDriver() {")
    let coreDriver = try Self.functionDefinition(
      in: Family.hierCorePath, atLine: coreDriverLine, index: index)

    // The cross-module call site: `coreDriver()` inside extCaller (HierExt).
    let coreDriverCallLine = try Self.uniqueLine(in: hierExt, containing: "coreDriver()")
    let callSite = try Self.callOccurrence(
      in: Family.hierExtPath, atLine: coreDriverCallLine, callee: coreDriver.symbol,
      index: index)
    #expect(
      callSite.symbolRoles & Int32(Scip_SymbolRole.readAccess.rawValue) != 0,
      "the coreDriver() call site must carry the ReadAccess bit — got roles \(callSite.symbolRoles)"
    )

    // And both hops of the in-module chain head: coreDriver's own calls.
    let circleInitCallLine = try Self.uniqueLine(in: hierCore, containing: "Circle(radius: 1)")
    let drawAllCallLine = try Self.uniqueLine(in: hierCore, containing: "drawAll([circle])")
    let circleInit = try Self.functionDefinition(
      in: Family.hierCorePath,
      atLine: try Self.uniqueLine(in: hierCore, trimmedEquals: "public struct Circle: HierShape {"),
      index: index)
    let drawAll = try Self.functionDefinition(
      in: Family.hierCorePath,
      atLine: try Self.uniqueLine(in: hierCore, trimmedEquals: "func drawAll(_ items: [HierDrawable]) {"),
      index: index)
    for (line, callee, what) in [
      (circleInitCallLine, circleInit.symbol, "Circle(radius: 1)"),
      (drawAllCallLine, drawAll.symbol, "drawAll([circle])"),
    ] {
      let occurrence = try Self.callOccurrence(
        in: Family.hierCorePath, atLine: line, callee: callee, index: index)
      #expect(
        occurrence.symbolRoles & Int32(Scip_SymbolRole.readAccess.rawValue) != 0,
        "the \(what) call site must carry the ReadAccess bit — got roles \(occurrence.symbolRoles)"
      )
    }
  }

  // MARK: - Task 2: breadth — every function both directions

  @Test("every function's incoming and outgoing sets match the source-derived inventory")
  func callGraphMatchesSourceInventory() throws {
    let index = try Self.sharedIndex()
    let hierCore = try Self.hierCoreFixture()
    let hierExt = try Self.hierExtFixture()
    let graph = Self.deriveCallGraph(index)

    // The complete function inventory, hand-derived from the fixture source and
    // grounded: each row's symbol has exactly one definition occurrence, and the
    // source line at that position carries the declared shape. Every function,
    // method, initializer, and accessor of the fixture is enumerated — including
    // the raw-USR fallback-Term functions (default implementation, conditional-
    // conformance witnesses), which the kind arm of the function-family test
    // keeps visible to the walk.
    let inventory: [(path: String, fixture: Fixture, symbol: String, defFragment: String, callees: [String])] = [
      // HierCore — protocol requirements and conformances.
      (Family.hierCorePath, hierCore, Family.hierDrawableDraw, "func draw()", []),
      (Family.hierCorePath, hierCore, Family.hierShapeAreaGetter, "var area: Double { get }", []),
      (Family.hierCorePath, hierCore, Family.hierShapeDescribe, "func describe() -> String", []),
      (Family.hierCorePath, hierCore, Family.circleInit, "public struct Circle: HierShape {", []),
      (Family.hierCorePath, hierCore, Family.circleRadiusSetter, "public let radius: Double", []),
      (Family.hierCorePath, hierCore, Family.circleRadiusGetter, "public let radius: Double", []),
      (Family.hierCorePath, hierCore, Family.circleAreaGetter, "Double.pi * radius * radius", [
        Family.swiftDoublePiGetter, Family.swiftDoubleMultiply, Family.circleRadiusGetter,
      ]),
      (Family.hierCorePath, hierCore, Family.circleDraw, "func draw() {}", []),
      (Family.hierCorePath, hierCore, Family.rectInit, "struct Rect: HierShape, Equatable", []),
      (Family.hierCorePath, hierCore, Family.rectWidthSetter, "let width: Double", []),
      (Family.hierCorePath, hierCore, Family.rectWidthGetter, "let width: Double", []),
      (Family.hierCorePath, hierCore, Family.rectHeightSetter, "let height: Double", []),
      (Family.hierCorePath, hierCore, Family.rectHeightGetter, "let height: Double", []),
      (Family.hierCorePath, hierCore, Family.rectAreaGetter, "width * height", [
        Family.rectWidthGetter, Family.swiftDoubleMultiply, Family.rectHeightGetter,
      ]),
      (Family.hierCorePath, hierCore, Family.rectDescriptionGetter, "var description: String", [
        Family.swiftStringInit, Family.rectWidthGetter, Family.rectHeightGetter,
      ]),
      (Family.hierCorePath, hierCore, Family.rectEquals, "static func == (lhs: Rect, rhs: Rect)", [
        Family.rectWidthGetter, Family.swiftEquatableEquals, Family.swiftBoolAnd,
        Family.rectHeightGetter,
      ]),
      (Family.hierCorePath, hierCore, Family.rectDraw, "func draw() {}", []),
      // HierCore — the class chain.
      (Family.hierCorePath, hierCore, Family.baseWidgetFrameSetter, "var frame: String", []),
      (Family.hierCorePath, hierCore, Family.baseWidgetFrameGetter, "var frame: String", []),
      (Family.hierCorePath, hierCore, Family.baseWidgetInit, "init() {}", []),
      (Family.hierCorePath, hierCore, Family.baseWidgetRender, "func render() {}", []),
      (Family.hierCorePath, hierCore, Family.squareSideSetter, "let side: Double", []),
      (Family.hierCorePath, hierCore, Family.squareSideGetter, "let side: Double", []),
      (Family.hierCorePath, hierCore, Family.squareInit, "override init() {", [
        Family.squareSideSetter, Family.baseWidgetInit,
      ]),
      (Family.hierCorePath, hierCore, Family.squareFrameGetter, "\"square\" }", []),
      (Family.hierCorePath, hierCore, Family.squareFrameSetter, "set {}", []),
      (Family.hierCorePath, hierCore, Family.squareRender, "override func render() {}", []),
      (Family.hierCorePath, hierCore, Family.roundedSquareInit, "class RoundedSquare: Square {", []),
      (Family.hierCorePath, hierCore, Family.roundedSquareRender, "override func render() {}", []),
      // HierCore — the default implementation (raw-USR fallback Term; kind=method).
      (Family.hierCorePath, hierCore, Family.defaultImplTerm, "func describe() -> String { \"shape\" }", []),
      // HierCore — Wheel and Wrapper members.
      (Family.hierCorePath, hierCore, Family.wheelSpokesSetter, "public let spokes: Int", []),
      (Family.hierCorePath, hierCore, Family.wheelSpokesGetter, "public let spokes: Int", []),
      (Family.hierCorePath, hierCore, Family.wheelInit, "public init(spokes: Int) {", [
        Family.wheelSpokesSetter,
      ]),
      (Family.hierCorePath, hierCore, Family.wrapperInit, "struct Wrapper<T> {", []),
      (Family.hierCorePath, hierCore, Family.wrapperInnerSetter, "let inner: T", []),
      (Family.hierCorePath, hierCore, Family.wrapperInnerGetter, "let inner: T", []),
      // HierCore — the ObjC-rooted subclass (@objc members ride pseudo-module USRs).
      (Family.hierCorePath, hierCore, Family.objcAnimalInit, "class ObjCAnimal: NSObject {", []),
      (Family.hierCorePath, hierCore, Family.objcAnimalSound, "@objc func sound() -> String", []),
      // HierCore — the emoji-named conforming type.
      (Family.hierCorePath, hierCore, Family.paletteInit, "struct 🎨: HierShape {", []),
      (Family.hierCorePath, hierCore, Family.paletteAreaGetter, "var area: Double { 0 }", []),
      (Family.hierCorePath, hierCore, Family.paletteDraw, "func draw() {}", []),
      // HierCore — free functions, the call-chain trunk.
      (Family.hierCorePath, hierCore, Family.drawAll, "func drawAll(_ items: [HierDrawable]) {", [
        Family.hierDrawableDraw,
      ]),
      (Family.hierCorePath, hierCore, Family.renderWidget, "func renderWidget(_ widget: BaseWidget) {", [
        Family.baseWidgetRender,
      ]),
      (Family.hierCorePath, hierCore, Family.coreDriver, "public func coreDriver() {", [
        Family.circleInit, Family.drawAll,
        // The `[circle]` array-literal initializer call emits an occurrence-only
        // fallback Term (`s:Sa12arrayLiteralSayxGxd_tcfc`) — not answerable by
        // name (v1 Term limitation, accepted shape; see suite doc comment).
      ]),
      // HierCore — extension-declared Wheel conformance members.
      (Family.hierCorePath, hierCore, Family.wheelAreaGetter, "Double(spokes)", [
        Family.wheelSpokesGetter,
        // `Double(spokes)` is likewise a fallback Term here (`s:SdySdSicfc`) —
        // the one call site of the corpus that is not answerable by name.
      ]),
      (Family.hierCorePath, hierCore, Family.wheelDraw, "func draw() {}", []),
      // HierCore — conditional-conformance witnesses (fallback Terms; kind =
      // getter/method — the kind arm keeps them in the function family).
      (Family.hierCorePath, hierCore, Family.wrapperAreaGetterTerm, "inner.area", [
        Family.wrapperInnerGetter, Family.hierShapeAreaGetter,
      ]),
      (Family.hierCorePath, hierCore, Family.wrapperDrawTerm, "inner.draw()", [
        Family.wrapperInnerGetter, Family.hierDrawableDraw,
      ]),
      // HierExt.
      (Family.hierExtPath, hierExt, Family.glowableGlow, "func glow()", []),
      (Family.hierExtPath, hierExt, Family.wheelGlow, "func glow() {}", []),
      (Family.hierExtPath, hierExt, Family.circleDescriptionGetterExt, "public var description", [
        Family.swiftStringInit, Family.circleRadiusGetter,
      ]),
      (Family.hierExtPath, hierExt, Family.extCaller, "func extCaller() {", [
        Family.coreDriver,
      ]),
      (Family.hierExtPath, hierExt, Family.extCallerOfEmitted, "func extCallerOfCaller() {", [
        Family.extCaller,
      ]),
    ]

    var expectedOutgoing: [String: Set<String>] = [:]
    for row in inventory {
      // Structural grounding: exactly one definition occurrence, in the expected
      // document, on a source line carrying the declared shape.
      let definitions = index.allOccurrences.filter {
        $0.symbol == row.symbol && $0.isDefinition
      }
      #expect(
        definitions.count == 1,
        "\(row.symbol) must have exactly one definition occurrence, found \(definitions.count)"
      )
      if let definition = definitions.first {
        #expect(
          definition.relativePath == row.path,
          "\(row.symbol) must be defined in \(row.path), found \(definition.relativePath)"
        )
        let line = Int(definition.line)
        #expect(
          row.fixture.lines.indices.contains(line)
            && row.fixture.lines[line].contains(row.defFragment),
          "\(row.symbol) is defined at \(row.path):\(line), which must contain '\(row.defFragment)'"
        )
      }
      expectedOutgoing[row.symbol] = Set(row.callees)
    }

    // The chain head's display name pins the one emitted-string quirk of the
    // corpus (see Family.extCallerOfEmitted): the canonical string drops the
    // trailing repeated word of `extCallerOfCaller`, the demangled display name
    // does not.
    let quirkInfo = index.documentSymbols[Family.hierExtPath]?
      .first { $0.symbol == Family.extCallerOfEmitted }
    #expect(
      quirkInfo?.displayName == "HierExt.extCallerOfCaller() -> ()",
      "the extCallerOfCaller display name must stay truthful while its canonical string carries the word-substitution quirk — got \(quirkInfo?.displayName ?? "nil")"
    )

    // Direction A (outgoing): the derived function set equals the pinned
    // inventory, and every function's derived outgoing set equals its expected
    // set — empty for the actual leaves.
    let derivedFunctions = Set(graph.functionDefinitions.map(\.symbol))
    #expect(
      derivedFunctions == Set(expectedOutgoing.keys),
      "the derived function set must equal the pinned inventory — missing: \(Set(expectedOutgoing.keys).subtracting(derivedFunctions).sorted()), unexpected: \(derivedFunctions.subtracting(expectedOutgoing.keys).sorted())"
    )
    for (symbol, expected) in expectedOutgoing {
      #expect(
        (graph.outgoing[symbol] ?? []) == expected,
        "outgoing(\(symbol)) must be \(expected.sorted()), got \((graph.outgoing[symbol] ?? []).sorted())"
      )
    }

    // Direction B (incoming): the reverse grouping equals the reverse of the
    // pinned expected map — every expected caller/callee pair derivable, every
    // derivable pair expected.
    var expectedIncoming: [String: Set<String>] = [:]
    for (caller, callees) in expectedOutgoing {
      for callee in callees {
        expectedIncoming[callee, default: []].insert(caller)
      }
    }
    #expect(
      Set(graph.incoming.keys) == Set(expectedIncoming.keys),
      "the derived callee set must equal the pinned reverse — missing: \(Set(expectedIncoming.keys).subtracting(graph.incoming.keys).sorted()), unexpected: \(Set(graph.incoming.keys).subtracting(expectedIncoming.keys).sorted())"
    )
    for (callee, expected) in expectedIncoming {
      #expect(
        graph.incoming[callee] == expected,
        "incoming(\(callee)) must be \(expected.sorted()), got \((graph.incoming[callee] ?? []).sorted())"
      )
    }
  }

  @Test("dynamic-dispatch sites attribute and resolve with ReadAccess (existential + virtual + generic)")
  func dynamicDispatchCallSitesResolve() throws {
    let index = try Self.sharedIndex()
    let hierCore = try Self.hierCoreFixture()
    let graph = Self.deriveCallGraph(index)

    // The store carries receiver/dispatch metadata (.dyn + recBy rows, RESEARCH
    // Q2) — but the EMITTED surface is the call occurrence + access bit, which
    // is exactly what this derivation uses. Three dispatch flavors:

    // (1) Existential protocol dispatch: `item.draw()` inside drawAll.
    let existentialLine = try Self.uniqueLine(in: hierCore, containing: "item.draw()")
    let existentialSite = try Self.callOccurrence(
      in: Family.hierCorePath, atLine: existentialLine, callee: Family.hierDrawableDraw,
      index: index)
    #expect(
      existentialSite.carriesReadAccess,
      "the existential draw() call site must carry the ReadAccess bit — got roles \(existentialSite.symbolRoles)"
    )
    #expect(
      graph.outgoing[Family.drawAll] == [Family.hierDrawableDraw],
      "the protocol-dispatched draw() resolves through the emitted occurrence data"
    )
    #expect(
      graph.attributedCallSites.contains { $0.caller == Family.drawAll && $0.occurrence == existentialSite },
      "the existential draw() call site attributes to drawAll"
    )

    // (2) Class-chain virtual dispatch: `widget.render()` inside renderWidget.
    let virtualLine = try Self.uniqueLine(in: hierCore, containing: "widget.render()")
    let virtualSite = try Self.callOccurrence(
      in: Family.hierCorePath, atLine: virtualLine, callee: Family.baseWidgetRender,
      index: index)
    #expect(
      virtualSite.carriesReadAccess,
      "the virtual render() call site must carry the ReadAccess bit — got roles \(virtualSite.symbolRoles)"
    )
    #expect(
      graph.outgoing[Family.renderWidget] == [Family.baseWidgetRender],
      "the virtual render() call resolves through the emitted occurrence data"
    )
    #expect(
      graph.attributedCallSites.contains { $0.caller == Family.renderWidget && $0.occurrence == virtualSite },
      "the virtual render() call site attributes to renderWidget"
    )

    // (3) Generic-constraint dispatch: `inner.draw()` inside the conditional-
    // conformance witness (a fallback-Term function — visible via its kind).
    let genericLine = try Self.uniqueLine(in: hierCore, containing: "inner.draw()")
    let genericSite = try Self.callOccurrence(
      in: Family.hierCorePath, atLine: genericLine, callee: Family.hierDrawableDraw,
      index: index)
    #expect(
      genericSite.carriesReadAccess,
      "the generic draw() call site must carry the ReadAccess bit — got roles \(genericSite.symbolRoles)"
    )
    #expect(
      graph.attributedCallSites.contains { $0.caller == Family.wrapperDrawTerm && $0.occurrence == genericSite },
      "the generic draw() call site attributes to the conditional-conformance witness"
    )
  }

  @Test("attribution invariants: exhaustive, exactly-once, leaves empty, callers are definitions")
  func attributionInvariantsHold() throws {
    let index = try Self.sharedIndex()
    let graph = Self.deriveCallGraph(index)

    // Exhaustive + exactly-once: every function-family non-definition occurrence
    // that carries an access bit is attributed exactly once (a call site with no
    // preceding function definition in its document would be silently dropped —
    // the count comparison catches it; the walk attributes each occurrence to
    // exactly one scope by construction). The function-family occurrences the
    // walk skips are exactly the role-0 implicit availability rows.
    let callableReferences = index.allOccurrences.filter {
      index.isFunctionFamily($0.symbol) && !$0.isDefinition && $0.carriesAccess
    }
    let implicitFunctionOccurrences = index.allOccurrences.filter {
      index.isFunctionFamily($0.symbol) && !$0.isDefinition && !$0.carriesAccess
    }
    #expect(
      !callableReferences.isEmpty,
      "the corpus must carry function-family reference occurrences"
    )
    #expect(
      graph.attributedCallSites.count == callableReferences.count,
      "every access-bearing function-family reference occurrence must be attributed exactly once — attributed \(graph.attributedCallSites.count), references \(callableReferences.count)"
    )
    // The skipped rows are exactly the implicit default-implementation
    // availability occurrences (RESEARCH pitfall 2, pinned as NON-edges by
    // RelationshipParity) — every one carries no role bit at all.
    #expect(
      implicitFunctionOccurrences.allSatisfy { $0.symbolRoles == 0 },
      "function-family occurrences without an access bit must be role-0 implicit rows — got \(implicitFunctionOccurrences.filter { $0.symbolRoles != 0 }.map { "\($0.symbol) roles \($0.symbolRoles)" })"
    )

    // No phantom attribution: every caller is a function symbol that carries a
    // definition occurrence somewhere in the corpus (never a non-function
    // definition, never an undefined name).
    let definedFunctions = Set(
      index.allOccurrences
        .filter { $0.isDefinition && index.isFunctionFamily($0.symbol) }
        .map(\.symbol))
    for site in graph.attributedCallSites {
      #expect(
        definedFunctions.contains(site.caller),
        "attributed caller \(site.caller) must be a defined function of the corpus"
      )
      #expect(
        index.isFunctionFamily(site.occurrence.symbol),
        "attributed callee \(site.occurrence.symbol) must be function-family"
      )
    }
  }

  @Test("zero-emission guard: format stays 5 and relationships equal the committed table")
  func zeroEmissionGuard() throws {
    let index = try Self.sharedIndex()

    // This plan changes NO emission: the format version stays 5 (a byte change
    // would be a D-09 bump — out of scope here), and the relationships this
    // suite's build produces are exactly the committed relationship-table.json
    // rows the RelationshipParity oracle pins over the same fixture build path.
    // Goldens byte-stability is proven by ScipCLIGate and Determinism in the
    // same single `swift test` CI step (the plan's Task 4 full-suite run).
    #expect(
      SymbolFormatVersion.current == 5,
      "SymbolFormatVersion.current must stay 5 in this plan — a change means emission drift"
    )

    let tablePath = (Self.fixtureRepoPath() as NSString)
      .appendingPathComponent("relationship-table.json")
    let committed = try #require(
      try? Data(contentsOf: URL(fileURLWithPath: tablePath)),
      "missing \(tablePath) — the committed RelationshipParity golden"
    )
    let committedRows = try JSONDecoder().decode([RelationshipTableRow].self, from: committed)
    #expect(!committedRows.isEmpty, "the committed relationship table must not be empty")

    let built = Set(index.relationships.map(RelationshipTableRow.init))
    let committedSet = Set(committedRows)
    if built != committedSet {
      let missing = built.subtracting(committedSet).sorted().prefix(5)
      let stale = committedSet.subtracting(built).sorted().prefix(5)
      Issue.record(
        "this suite's build must reproduce the committed relationship table — new: \(missing), removed: \(stale)"
      )
    }
  }

  // MARK: - Built-index plumbing

  /// One flattened occurrence with its document path and 0-based position attached.
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

    var isDefinition: Bool { symbolRoles & Roles.definitionBit != 0 }
    var carriesReadAccess: Bool { symbolRoles & Roles.readAccessBit != 0 }
    var carriesAccess: Bool {
      symbolRoles & (Roles.readAccessBit | Roles.writeAccessBit) != 0
    }
  }

  /// One attributed call site: the callee occurrence plus the function definition
  /// the derivation attributes it to (the caller).
  private struct CallSite {
    let caller: String
    let occurrence: FlatOccurrence
  }

  /// The consumer-simulated call graph.
  private struct CallGraph {
    /// Every function-family definition symbol in scan order (may repeat across
    /// documents; the corpus defines each exactly once).
    let functionDefinitions: [FlatOccurrence]
    let attributedCallSites: [CallSite]
    /// function symbol -> set of callee symbols it calls.
    let outgoing: [String: Set<String>]
    /// callee symbol -> set of function symbols that call it.
    let incoming: [String: Set<String>]
  }

  /// The built index: occurrences grouped per document (position-ordered) plus
  /// the symbol-kind table over documents AND external_symbols — the two tables
  /// a SCIP consumer reads.
  private struct BuiltIndex {
    let documents: [String: [FlatOccurrence]]
    let allOccurrences: [FlatOccurrence]
    let documentSymbols: [String: [Scip_SymbolInformation]]
    let kinds: [String: Scip_SymbolInformation.Kind]
    let relationships: [FlatRelationshipEdge]

    init(_ index: Scip_Index) {
      var documents: [String: [FlatOccurrence]] = [:]
      var flat: [FlatOccurrence] = []
      var documentSymbols: [String: [Scip_SymbolInformation]] = [:]
      var kinds: [String: Scip_SymbolInformation.Kind] = [:]
      var edges: [FlatRelationshipEdge] = []
      for document in index.documents {
        let ordered = document.occurrences
          .map { FlatOccurrence(relativePath: document.relativePath, occurrence: $0) }
          .sorted { lhs, rhs in
            if lhs.line != rhs.line { return lhs.line < rhs.line }
            if lhs.startCharacter != rhs.startCharacter {
              return lhs.startCharacter < rhs.startCharacter
            }
            return lhs.symbol < rhs.symbol
          }
        documents[document.relativePath] = ordered
        flat.append(contentsOf: ordered)
        documentSymbols[document.relativePath] = document.symbols
        for info in document.symbols {
          kinds[info.symbol] = info.kind
          for relationship in info.relationships {
            edges.append(
              FlatRelationshipEdge(
                relativePath: document.relativePath, symbol: info.symbol,
                relationship: relationship))
          }
        }
      }
      for info in index.externalSymbols {
        kinds[info.symbol] = info.kind
        for relationship in info.relationships {
          edges.append(
            FlatRelationshipEdge(
              relativePath: "external_symbols", symbol: info.symbol,
              relationship: relationship))
        }
      }
      self.documents = documents
      self.allOccurrences = flat
      self.documentSymbols = documentSymbols
      self.kinds = kinds
      self.relationships = edges
    }

    /// The consumer's function-family test (see the suite doc comment for the
    /// kind-or-descriptor contract).
    func isFunctionFamily(_ symbol: String) -> Bool {
      if let kind = kinds[symbol] {
        switch kind {
        case .constructor, .function, .getter, .method, .setter: return true
        default: break
        }
      }
      return symbol.hasSuffix(").")
    }
  }

  /// One flattened relationship edge (the zero-emission guard's comparison unit).
  private struct FlatRelationshipEdge: Hashable {
    let relativePath: String
    let symbol: String
    let target: String
    let isReference: Bool
    let isImplementation: Bool

    init(
      relativePath: String, symbol: String, relationship: Scip_Relationship
    ) {
      self.relativePath = relativePath
      self.symbol = symbol
      self.target = relationship.symbol
      self.isReference = relationship.isReference
      self.isImplementation = relationship.isImplementation
    }
  }

  /// The nearest-preceding-definition attribution walk (the derivation REL-02
  /// promises a consumer can perform over the emitted data alone).
  private static func deriveCallGraph(_ index: BuiltIndex) -> CallGraph {
    var functionDefinitions: [FlatOccurrence] = []
    var attributed: [CallSite] = []
    var outgoing: [String: Set<String>] = [:]
    var incoming: [String: Set<String>] = [:]

    for occurrences in index.documents.sorted(by: { $0.key < $1.key }).map(\.value) {
      var currentFunction: FlatOccurrence? = nil
      for occurrence in occurrences {
        guard index.isFunctionFamily(occurrence.symbol) else { continue }
        if occurrence.isDefinition {
          currentFunction = occurrence
          functionDefinitions.append(occurrence)
          continue
        }
        // A function-family reference inside the current function scope that
        // carries an access bit: a call site (the emitted surface a consumer
        // reads — no Call bit exists). Occurrences with NO access bit are the
        // implicit availability rows (synthesized default-implementation
        // occurrences at conformance-declaration lines, RESEARCH pitfall 2 —
        // and the ObjC implicit-member flood): no consumer can read them as
        // references, so the derivation skips them exactly as the def-gated
        // emission does.
        guard occurrence.carriesAccess else { continue }
        if let caller = currentFunction {
          attributed.append(CallSite(caller: caller.symbol, occurrence: occurrence))
          outgoing[caller.symbol, default: []].insert(occurrence.symbol)
          incoming[occurrence.symbol, default: []].insert(caller.symbol)
        }
      }
    }

    return CallGraph(
      functionDefinitions: functionDefinitions,
      attributedCallSites: attributed,
      outgoing: outgoing,
      incoming: incoming)
  }

  /// The single function-family definition occurrence on a source line.
  private static func functionDefinition(
    in relativePath: String, atLine line: Int32, index: BuiltIndex
  ) throws -> FlatOccurrence {
    let definitions = (index.documents[relativePath] ?? []).filter {
      $0.line == line && $0.isDefinition && index.isFunctionFamily($0.symbol)
    }
    guard definitions.count == 1, let definition = definitions.first else {
      throw CallHierarchyAnchorError(
        "function definition at \(relativePath):\(line)",
        "expected exactly one function-family definition occurrence, found \(definitions.count): \(definitions.map(\.symbol))")
    }
    return definition
  }

  /// The call-site occurrence of `callee` on a source line.
  private static func callOccurrence(
    in relativePath: String, atLine line: Int32, callee: String, index: BuiltIndex
  ) throws -> FlatOccurrence {
    let sites = (index.documents[relativePath] ?? []).filter {
      $0.line == line && $0.symbol == callee && !$0.isDefinition
    }
    guard sites.count == 1, let site = sites.first else {
      throw CallHierarchyAnchorError(
        "call occurrence of \(callee) at \(relativePath):\(line)",
        "expected exactly one call occurrence, found \(sites.count)")
    }
    return site
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
      let built = BuiltIndex(try CallHierarchyAnswerabilityTests.buildFixtureIndex())
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
      .appendingPathComponent("scip-swift-call-hierarchy-\(UUID().uuidString)")
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
      throw CallHierarchyAnchorError(
        anchor, "\(fixture.relativePath):\(anchor) must match exactly one line, matched \(matches.map(\.offset))")
    }
    return Int32(index)
  }

  /// The unique 0-based line in `fixture` whose whitespace-trimmed text equals `needle`.
  private static func uniqueLine(in fixture: Fixture, trimmedEquals needle: String) throws -> Int32 {
    let matches = fixture.lines.enumerated().filter {
      $0.element.trimmingCharacters(in: .whitespaces) == needle
    }
    guard matches.count == 1, let index = matches.first?.offset else {
      throw CallHierarchyAnchorError(
        needle, "\(fixture.relativePath):\(needle) must match exactly one trimmed line, matched \(matches.map(\.offset))")
    }
    return Int32(index)
  }

  private struct CallHierarchyAnchorError: Error, CustomStringConvertible {
    let anchor: String
    let detail: String
    init(_ anchor: String, _ detail: String) {
      self.anchor = anchor
      self.detail = detail
    }
    var description: String { "CallHierarchy anchor '\(anchor)': \(detail)" }
  }

  // MARK: - Pinned symbol families (exact canonical strings)

  /// Exact canonical symbol strings for the call-graph inventory — the same
  /// strings the caret goldens and relationship-table.json carry.
  private enum Family {
    static let hierCorePath = "Sources/HierCore/HierCore.swift"
    static let hierExtPath = "Sources/HierExt/HierExt.swift"

    static let core = "scip-swift swiftpm HierCore . "
    static let ext = "scip-swift swiftpm HierExt . "
    static let swiftSystem = "scip-swift swift Swift \(ToolchainInfo.pinnedSwiftVersion) "

    // System callees (minted external symbols — kind=unspecified, family by
    // their `).` descriptor).
    static let swiftDoublePiGetter = swiftSystem + "Double#pi()."
    static let swiftDoubleMultiply = swiftSystem + "Double#`*`()."
    static let swiftStringInit = swiftSystem + "String#init()."
    static let swiftEquatableEquals = swiftSystem + "Equatable#`==`()."
    static let swiftBoolAnd = swiftSystem + "Bool#`&&`()."

    // Local protocol requirements.
    static let hierDrawableDraw = core + "HierDrawable#draw()."
    static let hierShapeAreaGetter = core + "HierShape#area()."
    static let hierShapeDescribe = core + "HierShape#describe()."

    // Circle members.
    static let circleInit = core + "Circle#init()."
    static let circleRadiusSetter = core + "Circle#`radius=`()."
    static let circleRadiusGetter = core + "Circle#radius()."
    static let circleAreaGetter = core + "Circle#area()."
    static let circleDraw = core + "Circle#draw()."
    static let circleDescriptionGetterExt = core + "Circle#description()."

    // Rect members.
    static let rectInit = core + "Rect#init()."
    static let rectWidthSetter = core + "Rect#`width=`()."
    static let rectWidthGetter = core + "Rect#width()."
    static let rectHeightSetter = core + "Rect#`height=`()."
    static let rectHeightGetter = core + "Rect#height()."
    static let rectAreaGetter = core + "Rect#area()."
    static let rectDescriptionGetter = core + "Rect#description()."
    static let rectEquals = core + "Rect#`==`()."
    static let rectDraw = core + "Rect#draw()."

    // The class chain.
    static let baseWidgetFrameSetter = core + "BaseWidget#`frame=`()."
    static let baseWidgetFrameGetter = core + "BaseWidget#frame()."
    static let baseWidgetInit = core + "BaseWidget#init()."
    static let baseWidgetRender = core + "BaseWidget#render()."
    static let squareSideSetter = core + "Square#`side=`()."
    static let squareSideGetter = core + "Square#side()."
    static let squareInit = core + "Square#init()."
    static let squareFrameGetter = core + "Square#frame()."
    static let squareFrameSetter = core + "Square#`frame=`()."
    static let squareRender = core + "Square#render()."
    static let roundedSquareInit = core + "RoundedSquare#init()."
    static let roundedSquareRender = core + "RoundedSquare#render()."

    // Fallback-Term functions (raw-USR forms, pinned as emitted — v1).
    static let defaultImplTerm = core + "`s:8HierCore0A5ShapePAAE8describeSSyF`."
    static let wrapperAreaGetterTerm = core + "`s:8HierCore7WrapperVA2A0A5ShapeRzlE4areaSdvg`."
    static let wrapperDrawTerm = core + "`s:8HierCore7WrapperVA2A0A5ShapeRzlE4drawyyF`."

    // Wheel and Wrapper members.
    static let wheelSpokesSetter = core + "Wheel#`spokes=`()."
    static let wheelSpokesGetter = core + "Wheel#spokes()."
    static let wheelInit = core + "Wheel#init()."
    static let wheelAreaGetter = core + "Wheel#area()."
    static let wheelDraw = core + "Wheel#draw()."
    static let wheelGlow = core + "Wheel#glow()."
    static let wrapperInit = core + "Wrapper#init()."
    static let wrapperInnerSetter = core + "Wrapper#`inner=`()."
    static let wrapperInnerGetter = core + "Wrapper#inner()."

    // The ObjC-rooted subclass (@objc members ride pseudo-module USRs, v1).
    static let objcAnimalInit =
      "scip-swift swiftpm HierCore@objc(cs)ObjCAnimal(im)init . init()."
    static let objcAnimalSound =
      "scip-swift swiftpm HierCore@objc(cs)ObjCAnimal(im)sound . `HierCore@objc(cs)ObjCAnimal(im)sound`()."

    // The emoji-named conforming type.
    static let paletteInit = core + "`🎨`#init()."
    static let paletteAreaGetter = core + "`🎨`#area()."
    static let paletteDraw = core + "`🎨`#draw()."

    // Free functions — the call-chain trunk.
    static let drawAll = core + "drawAll()."
    static let renderWidget = core + "renderWidget()."
    static let coreDriver = core + "coreDriver()."
    static let glowableGlow = ext + "Glowable#glow()."
    static let extCaller = ext + "extCaller()."

    /// Emitted-reality pin (pre-existing, OUT OF SCOPE for 04-03 — fixing it
    /// changes emitted bytes, i.e. a D-09 format bump): the USR of
    /// `func extCallerOfCaller()` carries a MIXED word-substitution mangling
    /// (`s:8HierExt011extCallerOfD0yyFd` — literal run `extCallerOf` plus a
    /// final uppercase word reference `D` for the repeated trailing word), and
    /// the parser's word reader consumes `011` as a single length prefix, so the
    /// reconstructed canonical name drops the trailing "Caller". The canonical
    /// string is `extCallerOf().` while the demangled display name stays
    /// truthful. Call answerability is unaffected — the definition occurrence,
    /// its exact positions, and every call edge over the symbol are intact.
    /// Pinned as-is; recorded in 04-03-SUMMARY as a watch item.
    static let extCallerOfEmitted = ext + "extCallerOf()."
  }

  // MARK: - Row identity

  /// One row of the committed relationship-expectation table (the RelationshipParity
  /// golden's stable field contract) — the zero-emission guard's comparison unit.
  private struct RelationshipTableRow: Codable, Equatable, Hashable, Comparable {
    let relativePath: String
    let symbol: String
    let target: String
    let isReference: Bool
    let isImplementation: Bool

    init(_ edge: FlatRelationshipEdge) {
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

  // MARK: - Role bits (Scip_SymbolRole raw values — Generated/Scip.pb.swift)

  private enum Roles {
    static let definitionBit: Int32 = Int32(Scip_SymbolRole.definition.rawValue)
    static let readAccessBit: Int32 = Int32(Scip_SymbolRole.readAccess.rawValue)
    static let writeAccessBit: Int32 = Int32(Scip_SymbolRole.writeAccess.rawValue)
  }
}
