import Testing

@testable import scip_swift

/// Requirement: SYM-03 / D-08 half 1 — the Phase-1 golden table replicated byte-exact in
/// Swift (the executable spec of the frozen scip-swift symbol scheme, ported verbatim from
/// `swift/internal/symbol/namer_test.go` — the table IS the spec; strings are never
/// re-derived). Also covers the local-symbol goldens, the empty-input error cases, the D-07
/// source-order overload rule, and the getter/zero-arg-method merge determinism (Pitfall 6).
@Suite("SymbolSchemeGolden")
struct SymbolSchemeGoldenTests {
  typealias Input = CanonicalSymbolFormatter.SymbolInput
  typealias Container = CanonicalSymbolFormatter.Container

  @Test("the 36-row Phase-1 golden table renders byte-exact", arguments: [
    // Row 1: SwiftPM module's own symbol (the target of `import MyMod`).
    (
      Input(module: "MyMod", name: "MyMod", kind: .module),
      "scip-swift swiftpm MyMod . MyMod/"
    ),
    // Row 2: system module (manager "swift", toolchain version).
    (
      Input(
        module: "Swift", isSystemModule: true, swiftToolchainVersion: "6.2.4", name: "Swift",
        kind: .module),
      "scip-swift swift Swift 6.2.4 Swift/"
    ),
    // Rows 3-6: top-level struct, enum, protocol, typealias.
    (Input(module: "MyMod", name: "Shape", kind: .struct), "scip-swift swiftpm MyMod . Shape#"),
    (Input(module: "MyMod", name: "Color", kind: .enum), "scip-swift swiftpm MyMod . Color#"),
    (
      Input(module: "MyMod", name: "Drawable", kind: .protocol),
      "scip-swift swiftpm MyMod . Drawable#"
    ),
    (
      Input(module: "MyMod", name: "FooAlias", kind: .typeAlias),
      "scip-swift swiftpm MyMod . FooAlias#"
    ),
    // Row 7: nested type — ContainerPath carries the outer ancestry.
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Outer", kind: .struct)],
        name: "Inner", kind: .struct),
      "scip-swift swiftpm MyMod . Outer#Inner#"
    ),
    // Row 8: top-level func.
    (Input(module: "MyMod", name: "parse", kind: .func), "scip-swift swiftpm MyMod . parse()."),
    // Row 9: method.
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Shape", kind: .struct)],
        name: "area", kind: .method),
      "scip-swift swiftpm MyMod . Shape#area()."
    ),
    // Row 10: overloads — index 0 renders no disambiguator, N>0 renders (+N).
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Shape", kind: .struct)],
        name: "resize", kind: .method, overloadIndex: 0),
      "scip-swift swiftpm MyMod . Shape#resize()."
    ),
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Shape", kind: .struct)],
        name: "resize", kind: .method, overloadIndex: 1),
      "scip-swift swiftpm MyMod . Shape#resize(+1)."
    ),
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Shape", kind: .struct)],
        name: "resize", kind: .method, overloadIndex: 2),
      "scip-swift swiftpm MyMod . Shape#resize(+2)."
    ),
    // Row 11: operators — "+" IS an identifier character (no escaping); "==" is not.
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Vec", kind: .struct)], name: "+",
        kind: .operator),
      "scip-swift swiftpm MyMod . Vec#+()."
    ),
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Vec", kind: .struct)], name: "==",
        kind: .operator),
      "scip-swift swiftpm MyMod . Vec#`==`()."
    ),
    // Row 12: init — the Swift-native name; overload disambiguation as row 10.
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Vec", kind: .struct)], name: "init",
        kind: .constructor),
      "scip-swift swiftpm MyMod . Vec#init()."
    ),
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Vec", kind: .struct)], name: "init",
        kind: .constructor, overloadIndex: 1),
      "scip-swift swiftpm MyMod . Vec#init(+1)."
    ),
    // Row 13: deinit.
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Vec", kind: .struct)], name: "deinit",
        kind: .destructor),
      "scip-swift swiftpm MyMod . Vec#deinit()."
    ),
    // Row 14: getter — reuses the property's Method-shaped descriptor; a same-named
    // zero-arg method renders the identical string (distinguished by Kind only).
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Shape", kind: .struct)],
        name: "area", kind: .getter),
      "scip-swift swiftpm MyMod . Shape#area()."
    ),
    // Row 15: setter — the source name is "area="; "=" is outside the simple-identifier set.
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Shape", kind: .struct)],
        name: "area=", kind: .setter),
      "scip-swift swiftpm MyMod . Shape#`area=`()."
    ),
    // Rows 16-18: terms — property, let, global var.
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Shape", kind: .struct)],
        name: "origin", kind: .property),
      "scip-swift swiftpm MyMod . Shape#origin."
    ),
    (Input(module: "MyMod", name: "origin", kind: .constant), "scip-swift swiftpm MyMod . origin."),
    (Input(module: "MyMod", name: "config", kind: .variable), "scip-swift swiftpm MyMod . config."),
    // Row 19: subscript with overload indices.
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Vec", kind: .struct)],
        name: "subscript", kind: .subscript),
      "scip-swift swiftpm MyMod . Vec#subscript()."
    ),
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Vec", kind: .struct)],
        name: "subscript", kind: .subscript, overloadIndex: 1),
      "scip-swift swiftpm MyMod . Vec#subscript(+1)."
    ),
    // Row 20: enum case — a value term.
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Color", kind: .enum)], name: "red",
        kind: .enumCase),
      "scip-swift swiftpm MyMod . Color#red."
    ),
    // Row 21: extension member, same module, any file (SYM-02) — the input shape is
    // identical to row 9: ContainerPath IS the extended type's ancestry.
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Shape", kind: .struct)],
        name: "area2", kind: .method),
      "scip-swift swiftpm MyMod . Shape#area2()."
    ),
    // Row 22: retroactive extension (SYM-02) — the member declared in module Utils on Shape
    // owned by module App lives under the OWNER module's package; a second same-named
    // retroactive method disambiguates as (+1).
    (
      Input(
        module: "App", containerPath: [Container(name: "Shape", kind: .struct)], name: "spike",
        kind: .method),
      "scip-swift swiftpm App . Shape#spike()."
    ),
    (
      Input(
        module: "App", containerPath: [Container(name: "Shape", kind: .struct)], name: "spike",
        kind: .method, overloadIndex: 1),
      "scip-swift swiftpm App . Shape#spike(+1)."
    ),
    // Row 23: protocol requirement method.
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Drawable", kind: .protocol)],
        name: "draw", kind: .protocolMethod),
      "scip-swift swiftpm MyMod . Drawable#draw()."
    ),
    // Rows 24-25: conformance witness and class override use their OWN paths.
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Circle", kind: .struct)],
        name: "draw", kind: .method),
      "scip-swift swiftpm MyMod . Circle#draw()."
    ),
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Dog", kind: .class)], name: "speak",
        kind: .method),
      "scip-swift swiftpm MyMod . Dog#speak()."
    ),
    // Row 26: generic type parameter — descriptors chain without separator.
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "Box", kind: .struct)], name: "T",
        kind: .typeParameter),
      "scip-swift swiftpm MyMod . Box#[T]"
    ),
    // Row 27: function parameter — the container is the Func.
    (
      Input(
        module: "MyMod", containerPath: [Container(name: "f", kind: .func)], name: "x",
        kind: .parameter),
      "scip-swift swiftpm MyMod . f().(x)"
    ),
    // Row 29: macro.
    (Input(module: "MyMod", name: "Preview", kind: .macro), "scip-swift swiftpm MyMod . Preview!"),
    // The 01-01 walking-skeleton tracer case, kept as a table row.
    (
      Input(
        module: "MyApp", containerPath: [Container(name: "Shape", kind: .struct)],
        name: "area", kind: .method, overloadIndex: 0),
      "scip-swift swiftpm MyApp . Shape#area()."
    ),
    // System module with an empty toolchain version: the version renders as ".".
    (
      Input(module: "Swift", isSystemModule: true, name: "Swift", kind: .module),
      "scip-swift swift Swift . Swift/"
    ),
  ])
  func goldenTable(input: Input, expected: String) {
    #expect(CanonicalSymbolFormatter.symbol(input) == expected)
  }

  @Test("empty module or empty name produces no symbol")
  func inputErrors() {
    #expect(
      CanonicalSymbolFormatter.symbol(
        Input(module: "", name: "area", kind: .method)) == nil)
    #expect(
      CanonicalSymbolFormatter.symbol(
        Input(module: "MyMod", name: "", kind: .struct)) == nil)
  }

  @Test("local symbol goldens (row 28)", arguments: [
    ("i", 0, "local i"),
    ("count", 2, "local count_2"),
    ("🚀", 0, "local _"),
    ("x", 1, "local x_1"),
  ])
  func localSymbols(sourceName: String, ordinal: Int, expected: String) {
    #expect(CanonicalSymbolFormatter.localSymbol(sourceName: sourceName, ordinal: ordinal) == expected)
  }

  @Test("overload indices are assigned in (relativePath, line, utf8Column) source order (D-07)")
  func overloadIndicesFollowSourceOrder() {
    // Two same-named methods in one container, declared in two different files; a reference
    // in a third file must render the same string as its definition (Pitfall 4).
    let table = OverloadTable(definitions: [
      OverloadTable.Definition(
        usr: "s:6MyMod5ShapeV6resizeSdyF", module: "MyMod", containerNames: ["Shape"],
        name: "resize", kind: .method, relativePath: "Sources/B.swift", line: 10, utf8Column: 4),
      OverloadTable.Definition(
        usr: "s:6MyMod5ShapeV6resizeSi_SitF", module: "MyMod", containerNames: ["Shape"],
        name: "resize", kind: .method, relativePath: "Sources/A.swift", line: 3, utf8Column: 2),
    ])

    // A.swift sorts before B.swift regardless of store/insertion order.
    #expect(table.index(forUSR: "s:6MyMod5ShapeV6resizeSi_SitF") == 0)
    #expect(table.index(forUSR: "s:6MyMod5ShapeV6resizeSdyF") == 1)
    // Same line: utf8Column breaks the tie.
    // Unknown USRs and non-Method families carry no disambiguator.
    #expect(table.index(forUSR: "s:6MyMod5ShapeV6unknownSdyF") == 0)
  }

  @Test("same-line definitions break ties by utf8Column (assumption A1)")
  func sameLineTieBreak() {
    let table = OverloadTable(definitions: [
      OverloadTable.Definition(
        usr: "usr-late-col", module: "MyMod", containerNames: [], name: "f", kind: .func,
        relativePath: "A.swift", line: 5, utf8Column: 20),
      OverloadTable.Definition(
        usr: "usr-early-col", module: "MyMod", containerNames: [], name: "f", kind: .func,
        relativePath: "A.swift", line: 5, utf8Column: 2),
    ])
    #expect(table.index(forUSR: "usr-early-col") == 0)
    #expect(table.index(forUSR: "usr-late-col") == 1)
  }

  @Test("a getter and a zero-arg method of the same name collapse to one SymbolInformation whose Kind is last-in-source-order (Pitfall 6)")
  func getterMethodMergeIsDeterministic() {
    let getter = Scip_SymbolInformation()
    getter.symbol = "scip-swift swiftpm MyMod . Shape#area()."
    getter.kind = .getter

    let method = Scip_SymbolInformation()
    method.symbol = "scip-swift swiftpm MyMod . Shape#area()."
    method.kind = .method

    // The getter is later in source order (line 10 vs 3): its Kind wins, regardless of the
    // order the occurrences stream in.
    let winnerFromGetterFirst = SCIPIndexBuilder.winningSymbolInformation([
      (getter, .init(relativePath: "A.swift", line: 10, utf8Column: 4)),
      (method, .init(relativePath: "A.swift", line: 3, utf8Column: 4)),
    ])
    #expect(winnerFromGetterFirst.kind == .getter)

    let winnerFromMethodFirst = SCIPIndexBuilder.winningSymbolInformation([
      (method, .init(relativePath: "A.swift", line: 3, utf8Column: 4)),
      (getter, .init(relativePath: "A.swift", line: 10, utf8Column: 4)),
    ])
    #expect(winnerFromMethodFirst.kind == .getter)
  }
}
