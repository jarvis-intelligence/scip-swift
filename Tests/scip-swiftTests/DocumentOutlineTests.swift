import Foundation
import Testing

@testable import scip_swift

/// Requirement: NAV-02 / D-19 (03-02) — the documentSymbols structural oracle.
///
/// The vertical slice proven here: for any fixture document, the outline a consumer
/// rebuilds from `document.symbols` + `enclosing_symbol` is correct.
///
/// Three structural gates (D-19 — programmatic, not caret-annotated; the snapshot
/// goldens remain the byte gate):
/// 1. **Exhaustive invariant** — every non-empty `enclosingSymbol` value is a member
///    of that same document's symbol set, for EVERY document of the built index.
///    `enclosing_symbol` is emitted only for local symbols (from the store's
///    `.childOf` relation, `SCIPIndexBuilder`'s locals branch); this sweep is the
///    exhaustive half of the outline guarantee.
/// 2. **Locals** — the `local <n>` parameter symbols of the overloaded free funcs
///    carry an `enclosingSymbol` that resolves to the enclosing overload's canonical
///    string inside the same document.
/// 3. **Per-file outline equality** — the nesting tree derived by splitting
///    `document.symbols` canonical strings on their descriptor suffixes (type `#`,
///    method `().`, term `.`, …) equals a hand-written expected outline literal.
///
/// Accepted v1 shapes the outline derivation encodes (documented, never "fixed"
/// here — see README "Known limitations"):
/// - Document-scoped `local <n>` symbols are excluded from the outline tree (they
///   attach through `enclosing_symbol`, asserted by the locals test).
/// - `kind == .parameter` entries are excluded: their canonical form is a file-level
///   raw-USR fallback Term (D-06) that cannot nest by symbol string. The exhaustive
///   invariant still covers them (they carry an empty `enclosingSymbol` today).
/// - Extension declarations emit a fallback-Term SymbolInformation (kind Extension)
///   that stays a file-level entry; their MEMBERS nest under the extended type's
///   path (SYM-02), possibly across files — the extended type itself may then be a
///   path-only node (nil kind) in the extending file's outline.
/// - Generic type parameters DO emit a definition under the TypeAlias kind (WR-05's
///   accepted misclassification) — `Box#T#` nests under `Box#`.
@Suite("DocumentOutline")
struct DocumentOutlineTests {

  // MARK: - Test 1: exhaustive enclosing_symbol-membership invariant

  @Test("every non-empty enclosingSymbol resolves inside its own document (exhaustive)")
  func enclosingSymbolMembershipInvariant() throws {
    let index = try Self.sharedIndex()

    for document in index.documents {
      let symbolSet = Set(document.symbols.map(\.symbol))
      #expect(!symbolSet.isEmpty, "\(document.relativePath) must carry document symbols")

      for info in document.symbols where !info.enclosingSymbol.isEmpty {
        // enclosing_symbol stays locals-only in this phase (frozen emission shape):
        // only `local <n>` symbols may carry it at all.
        #expect(
          info.symbol.hasPrefix("local "),
          "only local symbols may carry enclosing_symbol, but \(info.symbol) in \(document.relativePath) does"
        )
        #expect(
          symbolSet.contains(info.enclosingSymbol),
          "dangling enclosingSymbol — document \(document.relativePath), symbol \(info.symbol), enclosing target \(info.enclosingSymbol) is not in the document's symbol set"
        )
      }
    }
  }

  // MARK: - Test 2: locals point at their enclosing overload, in-document

  @Test("locals carry enclosing_symbol at their enclosing parse overload, present in-document")
  func localsEnclosingSymbol() throws {
    let index = try Self.sharedIndex()
    let document = try Self.document("Sources/SchemeFixture/SchemeFixture.swift", in: index)
    let symbolSet = Set(document.symbols.map(\.symbol))

    func requireInfo(_ symbol: String) throws -> Scip_SymbolInformation {
      try #require(
        document.symbols.first { $0.symbol == symbol },
        "\(symbol) must be a document symbol of SchemeFixture.swift"
      )
    }

    // `local text` lives inside the FIRST parse overload — its enclosing target is
    // that overload's canonical string, unambiguous at index 0.
    let text = try requireInfo("local text")
    #expect(!text.enclosingSymbol.isEmpty, "`local text` must carry an enclosing_symbol")
    #expect(
      symbolSet.contains(text.enclosingSymbol),
      "`local text` enclosing target must be present in the same document"
    )
    #expect(
      text.enclosingSymbol == "scip-swift swiftpm SchemeFixture . parse().",
      "`local text` must be enclosed by parse(_: String) — got \(text.enclosingSymbol)"
    )

    // `local value_1` lives inside the SECOND parse overload. Emitted reality (the
    // committed caret goldens carry the same bytes): the enclosing target renders
    // the UN-disambiguated overload-group form `parse().`, because the locals branch
    // assembles the childOf symbol without the overload index. Asserting that exact
    // shape (not the idealized `parse(+1).`) keeps this oracle honest; a future
    // emission fix flipping it to the (+N) form fails here loudly and gets reviewed
    // with the D-09 format bump it would require.
    let value = try requireInfo("local value_1")
    #expect(!value.enclosingSymbol.isEmpty, "`local value_1` must carry an enclosing_symbol")
    #expect(
      symbolSet.contains(value.enclosingSymbol),
      "`local value_1` enclosing target must be present in the same document"
    )
    #expect(
      value.enclosingSymbol == "scip-swift swiftpm SchemeFixture . parse().",
      "`local value_1` enclosing target is the un-disambiguated overload-group form — got \(value.enclosingSymbol)"
    )
    // And it is at least the right overload FAMILY: a target pointing at any other
    // function fails here.
    #expect(
      value.enclosingSymbol.hasSuffix(" parse().")
        || value.enclosingSymbol.hasSuffix(" parse(+1)."),
      "`local value_1` must be enclosed by a parse overload — got \(value.enclosingSymbol)"
    )
  }

  // MARK: - Test 3: baseline outline equality for SchemeFixture.swift

  @Test("SchemeFixture.swift outline equals the hand-written expected tree")
  func baselineOutlineMatches() throws {
    let index = try Self.sharedIndex()
    let document = try Self.document("Sources/SchemeFixture/SchemeFixture.swift", in: index)

    let derived = Self.outline(of: document)
    #expect(
      derived.unparseable.isEmpty,
      "every outline symbol must split on its descriptor suffixes — unparseable: \(derived.unparseable)"
    )

    let expected: [OutlineNode] = [
      // Module root: the canonical header is the outline's root.
      .module("scip-swift swiftpm SchemeFixture .", [
        // Vec — stored properties with their accessor trios, overloaded inits,
        // operators (escaped "==" vs bare "+"), and the SAME-FILE extension member
        // length() riding the extended type's path (SYM-02).
        .node("Vec#", .struct, [
          .node("x.", .property), .node("x().", .getter), .node("`x=`().", .setter),
          .node("y.", .property), .node("y().", .getter), .node("`y=`().", .setter),
          .node("init().", .constructor), .node("init(+1).", .constructor),
          .node("`==`().", .staticMethod), .node("+().", .staticMethod),
          .node("length().", .method),
        ]),
        // Box — generic type; the type parameter nests under the type with the
        // accepted TypeAlias kind (WR-05).
        .node("Box#", .struct, [
          .node("T#", .typeAlias),
          .node("content.", .property), .node("content().", .getter),
          .node("`content=`().", .setter),
          .node("init().", .constructor), .node("unwrap().", .method),
        ]),
        .node("Drawable#", .protocol, [.node("draw().", .method)]),
        .node("Poster#", .class, [
          .node("label.", .property), .node("label().", .getter),
          .node("`label=`().", .setter),
          .node("init().", .constructor), .node("draw().", .method),
        ]),
        // Observed — accessors include the explicit get/set pair and the willSet,
        // which renders the setter-family `watched=`(+1) descriptor.
        .node("Observed#", .class, [
          .node("backing.", .property), .node("backing().", .getter),
          .node("`backing=`().", .setter),
          .node("computed.", .property), .node("computed().", .getter),
          .node("`computed=`().", .setter),
          .node("watched.", .property), .node("watched().", .getter),
          .node("`watched=`().", .setter), .node("`watched=`(+1).", .setter),
          .node("prepared.", .property), .node("prepared().", .getter),
          .node("`prepared=`().", .setter),
          .node("init().", .constructor),
        ]),
        .node("Spectrum#", .enum, [
          .node("red.", .enumMember), .node("green.", .enumMember),
          .node("blue.", .enumMember),
        ]),
        .node("Point#", .typeAlias),
        .node("parse().", .function), .node("parse(+1).", .function),
        // Subscript declarations keep the raw-USR fallback Terms (WR-01): the
        // declaration and its getter are file-level entries that cannot nest by
        // symbol string.
        .node("`s:13SchemeFixture3VecVyS2icip`.", .subscript),
        .node("`s:13SchemeFixture3VecVyS2icig`.", .getter),
        // The same-file `extension Vec` declaration itself: fallback Term with kind
        // Extension, a file-level entry (accepted v1 shape) — while its member
        // length() nests under Vec# above.
        .node("`s:e:s:13SchemeFixture3VecV6lengthSdyF`.", .extension),
        .node("`🚀`.", .variable), .node("`🚀`().", .getter), .node("`🚀=`().", .setter),
        .node("`π`.", .variable), .node("`π`().", .getter), .node("`π=`().", .setter),
        .node("`名前を付ける`().", .function),
        // #if-wrapped declaration — emitted like any other (no special casing).
        .node("conditionallyCompiled().", .function),
        .node("flagSequence.", .variable), .node("flagSequence().", .getter),
        .node("`flagSequence=`().", .setter),
        // Lattice — the deep-nesting section (03-02): enum → struct → class →
        // nested enum, with members at every level.
        .node("Lattice#", .enum, [
          // static let renders the staticProperty kind (not variable).
          .node("origin.", .staticProperty), .node("origin().", .getter),
          .node("`origin=`().", .setter),
          .node("Cell#", .struct, [
            .node("template.", .staticProperty), .node("template().", .getter),
            .node("`template=`().", .setter),
            // Cell declares no init: the compiler-synthesized default initializer
            // emits as an implicit definition — part of the derived outline.
            .node("init().", .constructor),
            .node("Core#", .class, [
              .node("metric.", .property), .node("metric().", .getter),
              .node("`metric=`().", .setter),
              .node("init().", .constructor),
              .node("doubled.", .property), .node("doubled().", .getter),
              .node("calibrated.", .property), .node("calibrated().", .getter),
              .node("`calibrated=`().", .setter),
              .node("reset().", .method),
              .node("Phase#", .enum, [
                .node("idle.", .enumMember), .node("active.", .enumMember),
              ]),
            ]),
          ]),
        ]),
      ]),
    ]

    #expect(
      Self.normalized(derived.roots) == Self.normalized(expected),
      "SchemeFixture.swift outline mismatch — derived:\n\(derived.roots.description)\nexpected:\n\(expected.description)"
    )
  }


  // MARK: - Task 2: deep nesting, extensions, accepted-limitation guards

  @Test("deep-nesting section nests four container levels under Lattice#")
  func deepNestingOutlineMatches() throws {
    let index = try Self.sharedIndex()
    let document = try Self.document("Sources/SchemeFixture/SchemeFixture.swift", in: index)

    let derived = Self.outline(of: document)
    #expect(derived.unparseable.isEmpty, "unparseable outline symbols: \(derived.unparseable)")

    let lattice = try #require(
      Self.normalized(derived.roots)
        .flatMap { node in node.children }
        .first { $0.descriptor == "Lattice#" },
      "the derived outline must carry the Lattice# container"
    )

    // The frozen scheme's nested-type form (namer row 7, Outer#Middle#Inner#):
    // every level renders its own type descriptor, members nest under the FULL
    // container chain — nothing flattens at depth.
    let expected = OutlineNode.node("Lattice#", .enum, [
      .node("origin.", .staticProperty), .node("origin().", .getter),
      .node("`origin=`().", .setter),
      .node("Cell#", .struct, [
        .node("template.", .staticProperty), .node("template().", .getter),
        .node("`template=`().", .setter),
        .node("init().", .constructor),  // compiler-synthesized default init
        .node("Core#", .class, [
          .node("metric.", .property), .node("metric().", .getter),
          .node("`metric=`().", .setter),
          .node("init().", .constructor),
          .node("doubled.", .property), .node("doubled().", .getter),
          .node("calibrated.", .property), .node("calibrated().", .getter),
          .node("`calibrated=`().", .setter),
          .node("reset().", .method),
          .node("Phase#", .enum, [
            .node("idle.", .enumMember), .node("active.", .enumMember),
          ]),
        ]),
      ]),
    ])
    #expect(
      lattice.normalized() == expected.normalized(),
      "Lattice# subtree mismatch — derived:\n\(lattice.description)expected:\n\(expected.description)"
    )

    // The deepest chain is real: module → Lattice# → Cell# → Core# → Phase# →
    // idle. — five descriptor levels below the header.
    func depth(of node: OutlineNode) -> Int {
      1 + (node.children.map { depth(of: $0) }.max() ?? 0)
    }
    let maxDepth = depth(of: lattice)
    #expect(
      maxDepth >= 5,
      "Lattice# subtree must be at least 5 nodes deep (Lattice→Cell→Core→Phase→case); got \(maxDepth)"
    )
  }

  @Test("extension file: decls are file-level entries, members nest under extended types")
  func extensionFileOutline() throws {
    let index = try Self.sharedIndex()
    let document = try Self.document("Sources/SchemeFixtureExt/SchemeFixtureExt.swift", in: index)

    let derived = Self.outline(of: document)
    #expect(derived.unparseable.isEmpty, "unparseable outline symbols: \(derived.unparseable)")

    // Three module roots: the members attribute to the extended types' OWNING
    // modules (SYM-02) — Box/Vec under SchemeFixture, schemeShout under Swift's
    // system header — while the extension DECLARATIONS stay file-level fallback
    // Terms under this file's own module (accepted v1 shape: an Extension-kind
    // fallback Term cannot nest via its symbol string). The extended types are
    // path-only nodes (nil kind): their definitions live in other documents.
    let expected: [OutlineNode] = [
      .module("scip-swift swiftpm SchemeFixture .", [
        .node("Box#", nil, [.node("describe().", .method)]),
        .node("Vec#", nil, [
          .node("manhattanLength.", .property),
          .node("manhattanLength().", .getter),
        ]),
      ]),
      .module("scip-swift swiftpm SchemeFixtureExt .", [
        .node("`s:e:s:13SchemeFixture3BoxV0aB3ExtE8describeSSyF`.", .extension),
        .node("`s:e:s:13SchemeFixture3VecV0aB3ExtE15manhattanLengthSivp`.", .extension),
        .node("`s:e:s:SS16SchemeFixtureExtE11schemeShoutSSyF`.", .extension),
      ]),
      .module("scip-swift swift Swift \(ToolchainInfo.pinnedSwiftVersion)", [
        .node("String#", nil, [.node("schemeShout().", .method)]),
      ]),
    ]

    #expect(
      Self.normalized(derived.roots) == Self.normalized(expected),
      "SchemeFixtureExt.swift outline mismatch — derived:\n\(derived.roots.description)\nexpected:\n\(expected.description)"
    )
  }

  @Test("accepted v1 limitation guards: generic param shape and test-document locals")
  func acceptedLimitationGuards() throws {
    let index = try Self.sharedIndex()
    let library = try Self.document("Sources/SchemeFixture/SchemeFixture.swift", in: index)

    // Generic type parameters DO emit a definition — `Box#T#`, one per generic
    // type, under the TypeAlias kind (WR-05's accepted misclassification; there is
    // no store Symbol.Kind for genericTypeParam, so TypeParameter never renders).
    // The plan expected "no definition at all"; emitted reality (committed goldens
    // + symbol-table.json parity records) is a definition under the wrong kind —
    // asserted here as the accepted shape so any change fails loudly.
    let genericParamDefinitions = library.symbols.filter { $0.symbol.hasSuffix("#T#") }
    #expect(
      genericParamDefinitions.count == 1,
      "exactly one generic type-parameter definition expected — got \(genericParamDefinitions.map(\.symbol))"
    )
    #expect(
      genericParamDefinitions.first?.symbol == "scip-swift swiftpm SchemeFixture . Box#T#",
      "the generic type parameter must render under Box#'s path — got \(genericParamDefinitions.map(\.symbol))"
    )
    #expect(
      genericParamDefinitions.first?.kind == .typeAlias,
      "Box#T# keeps the TypeAlias kind (WR-05 accepted misclassification)"
    )

    // Swift-Testing documents contribute no local-property symbols: the store
    // emits no `.local` occurrences for test-file declarations on this toolchain,
    // so enclosing_symbol coverage there is empty and the exhaustive invariant
    // holds trivially — asserted explicitly, not assumed.
    let testDocument = try #require(
      index.documents.first { $0.relativePath == "Tests/SchemeFixtureTests/SchemeFixtureTests.swift" },
      "the Swift-Testing document must be indexed"
    )
    let localSymbols = testDocument.symbols.filter { $0.symbol.hasPrefix("local ") }
    #expect(
      localSymbols.isEmpty,
      "the Swift-Testing document must carry no `local n` symbols — got \(localSymbols.map(\.symbol))"
    )
    let withEnclosing = testDocument.symbols.filter { !$0.enclosingSymbol.isEmpty }
    #expect(
      withEnclosing.isEmpty,
      "the Swift-Testing document must carry no enclosing_symbol entries — got \(withEnclosing.map(\.symbol))"
    )
  }

  // MARK: - Outline model

  /// One node of a derived (or expected) outline: the descriptor text (`Vec#`,
  /// `x().`, `` `s:…`. ``), the symbol's kind when the node is a document symbol of
  /// this file (nil for path-only ancestors — e.g. `Box#` inside the extending
  /// file's outline), and nested children.
  struct OutlineNode: Equatable, CustomStringConvertible {
    let descriptor: String
    var kind: Scip_SymbolInformation.Kind?
    var children: [OutlineNode]

    var description: String {
      func render(_ node: OutlineNode, depth: Int) -> String {
        let kindText = node.kind.map { " [\($0)]" } ?? ""
        let line = String(repeating: "  ", count: depth) + node.descriptor + kindText + "\n"
        return line + node.children.map { render($0, depth: depth + 1) }.joined()
      }
      return children.map { render($0, depth: 0) }.joined()
    }

    /// Order-insensitive normalization: children sorted by descriptor, recursively.
    /// (document.symbols order is separately pinned ascending by the Determinism
    /// suite; the outline oracle proves the TREE, not the byte order.)
    func normalized() -> OutlineNode {
      var copy = self
      copy.children = copy.children.map { $0.normalized() }
        .sorted { $0.descriptor < $1.descriptor }
      return copy
    }

    static func module(_ header: String, _ children: [OutlineNode]) -> OutlineNode {
      OutlineNode(descriptor: header, kind: nil, children: children)
    }

    static func node(
      _ descriptor: String,
      _ kind: Scip_SymbolInformation.Kind?,
      _ children: [OutlineNode] = []
    ) -> OutlineNode {
      OutlineNode(descriptor: descriptor, kind: kind, children: children)
    }
  }

  /// Order-insensitive comparison for outline forests (see `OutlineNode.normalized`).
  private static func normalized(_ nodes: [OutlineNode]) -> [OutlineNode] {
    nodes.map { $0.normalized() }.sorted { $0.descriptor < $1.descriptor }
  }

  // MARK: - Outline derivation

  /// Mutable builder the forest is assembled in before freezing into `OutlineNode`s.
  private final class OutlineBuilder {
    var kind: Scip_SymbolInformation.Kind?
    var children: [String: OutlineBuilder] = [:]

    func freeze(descriptor: String) -> OutlineNode {
      OutlineNode(
        descriptor: descriptor,
        kind: kind,
        children: children
          .map { $0.value.freeze(descriptor: $0.key) }
          .sorted { $0.descriptor < $1.descriptor })
    }
  }

  /// Derives the outline forest of one document from its `document.symbols`
  /// canonical strings: one root per module header, children nested by descriptor
  /// chain. Locals (`local <n>`) and `.parameter` entries are excluded (documented
  /// accepted shapes — see the suite header); anything that fails to split is
  /// returned in `unparseable` so the caller can fail with the symbol in hand.
  static func outline(of document: Scip_Document)
    -> (roots: [OutlineNode], unparseable: [String])
  {
    var roots: [String: OutlineBuilder] = [:]
    var unparseable: [String] = []

    for info in document.symbols {
      let symbol = info.symbol
      if symbol.hasPrefix("local ") { continue }
      if info.kind == .parameter { continue }
      guard let (header, descriptors) = Self.splitCanonical(symbol) else {
        unparseable.append(symbol)
        continue
      }
      let root = roots[header] ?? OutlineBuilder()
      roots[header] = root
      var node = root
      for (index, descriptor) in descriptors.enumerated() {
        let child = node.children[descriptor] ?? OutlineBuilder()
        node.children[descriptor] = child
        if index == descriptors.count - 1 {
          child.kind = info.kind
        }
        node = child
      }
    }

    let forest = roots
      .map { $0.value.freeze(descriptor: $0.key) }
      .sorted { $0.descriptor < $1.descriptor }
    return (forest, unparseable)
  }

  /// Splits a canonical global symbol string into its module header and descriptor
  /// chain, honoring the frozen scheme's escaping: space fields are separated by a
  /// single space (a doubled space is an escaped space inside a field), descriptor
  /// names are bare identifier characters or backtick-quoted (backticks doubled
  /// inside quotes), and the suffix decides the descriptor family — type `#`,
  /// namespace `/`, term `.`, method `()`/`(+N)` + `.`, macro `!`, type parameter
  /// `[…]`, parameter `(…)`. Returns nil for anything else.
  static func splitCanonical(_ symbol: String) -> (header: String, descriptors: [String])? {
    let characters = Array(symbol)
    var index = 0

    // Header: four space-separated fields (scheme, manager, module, version), with
    // escaped (doubled) spaces inside a field.
    var fields: [String] = []
    for _ in 0..<4 {
      var field = ""
      var closed = false
      while index < characters.count {
        let character = characters[index]
        if character == " " {
          if index + 1 < characters.count, characters[index + 1] == " " {
            field.append(" ")
            index += 2
          } else {
            index += 1
            closed = true
            break
          }
        } else {
          field.append(character)
          index += 1
        }
      }
      fields.append(field)
      if !closed { return nil }  // truncated header
    }
    let header = fields.joined(separator: " ")

    var descriptors: [String] = []
    while index < characters.count {
      let start = index
      let character = characters[index]

      if character == "`" {
        // Quoted name: doubled backticks are escaped literal backticks.
        index += 1
        var closedQuote = false
        while index < characters.count {
          if characters[index] == "`" {
            if index + 1 < characters.count, characters[index + 1] == "`" {
              index += 2
              continue
            }
            index += 1
            closedQuote = true
            break
          }
          index += 1
        }
        guard closedQuote else { return nil }
      } else if character == "[" {
        // Type-parameter descriptor `[name]`.
        while index < characters.count, characters[index] != "]" { index += 1 }
        guard index < characters.count else { return nil }
        index += 1
        descriptors.append(String(characters[start..<index]))
        continue
      } else if character == "(" {
        // Parameter descriptor `(name)`.
        while index < characters.count, characters[index] != ")" { index += 1 }
        guard index < characters.count else { return nil }
        index += 1
        descriptors.append(String(characters[start..<index]))
        continue
      } else {
        // Bare name: identifier characters only (_ + - $, ASCII letters/digits).
        while index < characters.count {
          let c = characters[index]
          if c == "#" || c == "." || c == "(" || c == "/" || c == "!" { break }
          index += 1
        }
      }

      // The family suffix.
      guard index < characters.count else { return nil }
      switch characters[index] {
      case "#", "/", "!", ".":  // type, namespace, macro, term
        index += 1
      case "(":  // method: `()` or `(+N)`, then `.`
        while index < characters.count, characters[index] != ")" { index += 1 }
        guard index < characters.count else { return nil }
        index += 1
        guard index < characters.count, characters[index] == "." else { return nil }
        index += 1
      default:
        return nil
      }
      descriptors.append(String(characters[start..<index]))
    }

    guard !descriptors.isEmpty else { return nil }
    return (header, descriptors)
  }

  // MARK: - Built-index plumbing

  private static func document(
    _ relativePath: String, in index: Scip_Index
  ) throws -> Scip_Document {
    try #require(
      index.documents.first { $0.relativePath == relativePath },
      "\(relativePath) must be an indexed document"
    )
  }

  /// The built index is cached per test run: every test in this suite asserts over
  /// the same corpus, and one fixture build (a real `swift build --build-tests`) is
  /// enough.
  private static let indexBox = IndexBox()

  private static func sharedIndex() throws -> Scip_Index {
    try indexBox.get()
  }

  private final class IndexBox: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: Scip_Index?

    func get() throws -> Scip_Index {
      lock.lock()
      defer { lock.unlock() }
      if let cached { return cached }
      let built = try DocumentOutlineTests.buildFixtureIndex()
      cached = built
      return built
    }
  }

  /// Mirrors `ScipCLIGateTests.buildIndex` (it is private there): SwiftPMBuildRunner
  /// produces the index store, `swift build --build-tests` folds the test target
  /// into the same store, then the in-process SCIPIndexBuilder emits the Scip_Index.
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
      .appendingPathComponent("scip-swift-document-outline-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }
}
