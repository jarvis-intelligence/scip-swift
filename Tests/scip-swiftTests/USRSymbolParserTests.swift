import IndexStoreDB
import Testing

@testable import scip_swift

/// Requirement: SYM-03 / D-05 — the USR grammar corpus (spike-verified real USRs plus the
/// engine's own fixture USRs), the retroactive owner-module attribution rule, punycode and
/// operator decoding, accessor/constructor DeclKind mapping, and the D-06 totality posture
/// over adversarial input (T-02-01: the parser is total — bounded reads, no traps, nil on
/// any miss).
@Suite("USRSymbolParser")
struct USRSymbolParserTests {
  private let toolchain = ToolchainInfo.pinnedSwiftVersion

  private func makeSymbol(
    usr: String,
    name: String,
    kind: IndexSymbolKind,
    subKind: IndexSymbolSubKind = .none
  ) -> Symbol {
    Symbol(usr: usr, name: name, kind: kind, subKind: subKind, language: .swift)
  }

  private func canonical(
    _ usr: String, name: String, kind: IndexSymbolKind, subKind: IndexSymbolSubKind = .none,
    isSystemLocation: Bool = false
  ) -> String? {
    guard let parsed = USRSymbolParser.parse(usr) else { return nil }
    return USRSymbolMapper.canonicalSymbolString(
      parsed: parsed,
      symbol: makeSymbol(usr: usr, name: name, kind: kind, subKind: subKind),
      isSystemLocation: isSystemLocation,
      toolchainVersion: toolchain
    )
  }

  // MARK: - Grammar corpus (spike rows 1-3, 8, 12)

  @Test("method-on-struct USR parses to module, container, name")
  func methodOnStruct() throws {
    let parsed = try #require(USRSymbolParser.parse("s:16MiniSwiftPackage7GreeterV5greetSSyF"))
    #expect(parsed.module == "MiniSwiftPackage")
    #expect(!parsed.isSystemModule)
    #expect(parsed.containers.map(\.name) == ["Greeter"])
    #expect(parsed.containers.first?.kind == .struct)
    #expect(parsed.name == "greet")
  }

  @Test("retroactive extension attributes to the owner module, never the declaring module")
  func retroactiveExtensionAttributesToOwnerModule() throws {
    // s:SS17CapabilityFixtureE9spikeFlagSSyF: SS = String (Swift stdlib), 17CapabilityFixtureE
    // = the EXTENDING module. SYM-02: the emitted symbol uses the extended type's owner module
    // header — never the declaring file's module.
    let parsed = try #require(USRSymbolParser.parse("s:SS17CapabilityFixtureE9spikeFlagSSyF"))
    #expect(parsed.module == "Swift")
    #expect(parsed.isSystemModule)
    #expect(parsed.containers.map(\.name) == ["String"])
    #expect(parsed.name == "spikeFlag")
    #expect(parsed.extendingModule == "CapabilityFixture")

    let symbol = try #require(
      canonical(
        "s:SS17CapabilityFixtureE9spikeFlagSSyF", name: "spikeFlag()", kind: .instanceMethod))
    #expect(symbol == "scip-swift swift Swift \(toolchain) String#spikeFlag().")
    #expect(!symbol.contains("CapabilityFixture"), "the declaring module must not appear")
  }

  @Test("same-module cross-file extension keeps the extended type's path")
  func crossFileExtensionKeepsExtendedTypePath() throws {
    let parsed = try #require(USRSymbolParser.parse("s:17CapabilityFixture5ShapeV5area2SdyF"))
    #expect(parsed.module == "CapabilityFixture")
    #expect(parsed.containers.map(\.name) == ["Shape"])
    #expect(parsed.name == "area2")

    let symbol = try #require(
      canonical("s:17CapabilityFixture5ShapeV5area2SdyF", name: "area2()", kind: .instanceMethod))
    #expect(symbol == "scip-swift swiftpm CapabilityFixture . Shape#area2().")
  }

  @Test("word-substituted extending module decodes (retroactive on a user-module type)")
  func wordSubstitutedExtendingModule() throws {
    // Real USR shape from SchemeFixtureExt: the extending module shares words with the
    // extended type's module, so the mangler encodes it as `0<word-refs><literal>` —
    // `0aB3Ext` = Scheme(word 0) + Fixture(word 1, final ref) + literal "Ext". Verified
    // against `swift-demangle`: (extension in SchemeFixtureExt):SchemeFixture.Box.describe().
    let parsed = try #require(
      USRSymbolParser.parse("s:13SchemeFixture3BoxV0aB3ExtE8describeSSyF"))
    #expect(parsed.module == "SchemeFixture")
    #expect(!parsed.isSystemModule)
    #expect(parsed.containers.map(\.name) == ["Box"])
    #expect(parsed.containers.first?.kind == .struct)
    #expect(parsed.name == "describe")
    #expect(parsed.extendingModule == "SchemeFixtureExt")

    let symbol = try #require(
      canonical(
        "s:13SchemeFixture3BoxV0aB3ExtE8describeSSyF", name: "describe()", kind: .instanceMethod)
    )
    #expect(symbol == "scip-swift swiftpm SchemeFixture . Box#describe().")
  }

  @Test("fully substituted extending module uses the trailing-0 terminator form")
  func substitutedWordTerminatorForm() throws {
    // `0aB0`: My(word 0) + Mod(word 1, final ref) + the grammar's literal-`0` terminator
    // (no literal segment follows the final reference). Verified against `swift-demangle`:
    // (extension in MyMod):MyMod.Box.draw().
    let parsed = try #require(USRSymbolParser.parse("s:5MyMod3BoxV0aB0E4drawSSyF"))
    #expect(parsed.module == "MyMod")
    #expect(parsed.containers.map(\.name) == ["Box"])
    #expect(parsed.name == "draw")
    #expect(parsed.extendingModule == "MyMod")
  }

  @Test("punycode identifiers resolve to their real names")
  func punycodeIdentifiersResolve() throws {
    // 🚀 (U+1F680) mangles as 004BFIh; π (U+03C0) as 003Bxa (spike row 8).
    let rocket = try #require(USRSymbolParser.parse("s:17CapabilityFixture004BFIhSSyF"))
    #expect(rocket.module == "CapabilityFixture")
    #expect(rocket.name == "🚀")

    let pi = try #require(USRSymbolParser.parse("s:17CapabilityFixture003BxaSdvp"))
    #expect(pi.name == "π")

    let rocketSymbol = try #require(
      canonical("s:17CapabilityFixture004BFIhSSyF", name: "🚀()", kind: .function))
    #expect(rocketSymbol == "scip-swift swiftpm CapabilityFixture . `🚀`().")
    let piSymbol = try #require(
      canonical("s:17CapabilityFixture003BxaSdvp", name: "π", kind: .variable))
    #expect(piSymbol == "scip-swift swiftpm CapabilityFixture . `π`.")
  }

  @Test("stdlib String maps to the system-module header shape")
  func stdlibStringMapsToSystemHeader() throws {
    let parsed = try #require(USRSymbolParser.parse("s:SS"))
    #expect(parsed.module == "Swift")
    #expect(parsed.isSystemModule)
    #expect(parsed.containers.isEmpty)
    #expect(parsed.name == "String")

    let symbol = try #require(canonical("s:SS", name: "String", kind: .struct))
    #expect(symbol == "scip-swift swift Swift \(toolchain) String#")
  }

  // MARK: - Accessors, constructors, operators

  @Test("accessor USRs yield Getter/Setter DeclKinds; the setter name is synthesized")
  func accessorsMapToDeclKinds() throws {
    #expect(
      canonical(
        "s:16MiniSwiftPackage7GreeterV4nameSSvg", name: "getter:name", kind: .instanceProperty,
        subKind: .accessorGetter
      ) == "scip-swift swiftpm MiniSwiftPackage . Greeter#name().")

    // Assumption A5: the setter source name is `name=` synthesized from the property name,
    // never copied from the USR/store ("setter:name").
    #expect(
      canonical(
        "s:16MiniSwiftPackage7GreeterV4nameSSvs", name: "setter:name", kind: .instanceProperty,
        subKind: .accessorSetter
      ) == "scip-swift swiftpm MiniSwiftPackage . Greeter#`name=`().")

    #expect(
      canonical(
        "s:16MiniSwiftPackage7GreeterV4nameSSvW", name: "willSet:name", kind: .instanceProperty,
        subKind: .swiftAccessorWillSet
      ) == "scip-swift swiftpm MiniSwiftPackage . Greeter#`name=`().")

    // The property's own declaration (vp) is a Term.
    #expect(
      canonical(
        "s:16MiniSwiftPackage7GreeterV4nameSSvp", name: "name", kind: .instanceProperty)
      == "scip-swift swiftpm MiniSwiftPackage . Greeter#name.")
  }

  @Test("constructor USRs yield the Constructor DeclKind under the container's path")
  func constructorsMapToDeclKind() throws {
    // Label-less init(): ACycfc carries no name word — the kind supplies "init".
    #expect(
      canonical(
        "s:20DocumentationFixture10DocumentedCACycfc", name: "init()", kind: .constructor)
      == "scip-swift swiftpm DocumentationFixture . Documented#init().")

    // Labelled init(name:): the USR's word is the argument label; the kind still supplies
    // "init".
    #expect(
      canonical(
        "s:16MiniSwiftPackage7GreeterV4nameACSS_tcfc", name: "init(name:)", kind: .constructor)
      == "scip-swift swiftpm MiniSwiftPackage . Greeter#init().")

    #expect(
      canonical(
        "s:20DocumentationFixture10DocumentedCfd", name: "deinit", kind: .destructor)
      == "scip-swift swiftpm DocumentationFixture . Documented#deinit().")
  }

  @Test("operators classify by name shape into the Method family; escaping is the formatter's")
  func operatorsClassifyByNameShape() throws {
    // `static func ==` mangles the operator as `2eeoi` (assumption A4: operator-ness comes
    // from the store name's shape, not the mangling; backtick escaping is left to the
    // formatter).
    #expect(
      canonical(
        "s:17CapabilityFixture3VecC2eeoiySbAC_ACtFZ", name: "==(_:_:)", kind: .classMethod)
      == "scip-swift swiftpm CapabilityFixture . Vec#`==`().")

    // "+" IS an identifier character (no escaping).
    #expect(
      canonical(
        "s:17CapabilityFixture3VecC1poiyA2C_ACtFZ", name: "+(A:B:)", kind: .classMethod)
      == "scip-swift swiftpm CapabilityFixture . Vec#+().")
  }


  // MARK: - Module import USRs (c:@M@, SYM-04 / D-17, 03-03)

  @Test("module import USR parses to a bare module ParsedUSR")
  func moduleImportUSRParses() throws {
    let parsed = try #require(USRSymbolParser.parse("c:@M@SchemeFixture"))
    #expect(parsed.module == "SchemeFixture")
    #expect(parsed.containers.isEmpty)
    #expect(parsed.name == "SchemeFixture")
    #expect(parsed.extendingModule == nil)
    #expect(!parsed.isOperator)
    // Membership is the caller's decision (PackageTargetMap supplies it through
    // isSystemLocation) — the production stays pure and parses only the name.
    #expect(!parsed.isSystemModule)
  }

  @Test("module import USR maps to the swiftpm form for local targets")
  func moduleImportUSRLocalTargetForm() throws {
    let symbol = try #require(
      canonical("c:@M@SchemeFixture", name: "SchemeFixture", kind: .module))
    #expect(symbol == "scip-swift swiftpm SchemeFixture . SchemeFixture/")
  }

  @Test("module import USR maps to the swift+pin form for external modules")
  func moduleImportUSRExternalForm() throws {
    let symbol = try #require(
      canonical("c:@M@Foundation", name: "Foundation", kind: .module, isSystemLocation: true))
    #expect(symbol == "scip-swift swift Foundation \(toolchain) Foundation/")
  }

  @Test("empty c:@M@ remainder stays unparseable (D-06 fallback)")
  func emptyModuleUSRStaysUnparseable() {
    #expect(USRSymbolParser.parse("c:@M@") == nil)
  }

  // MARK: - D-06 totality over adversarial input (T-02-01)

  @Test("rune soup, huge claimed lengths, and truncation never crash and return nil")
  func adversarialInputIsTotal() {
    let adversarial: [String] = [
      "",
      "s",
      "s:",
      "s:0",
      "s:00",
      "s:004",  // punycode length claimed, no characters
      "s:999999x",  // claimed length far beyond the input
      "s:99999999999999999999word",  // claimed length overflows any Int
      "s:12Min",  // module length claimed, truncated
      "s:7GreeterV4name",  // name length claimed, truncated
      "s:🎉🎉🎉",  // multi-byte runes in the module position
      "s:16MiniSwiftPackage🎉🎉",  // multi-byte runes inside a word
      "s:16Mini SwiftPackage",  // space inside the identifier region
      "s:-5word",  // negative-ish length marker
      "c:objc(cs)NSObject",  // non-Swift scheme
      "so: NSObject",  // non-Swift scheme with space
      "_:$s16MiniSwiftPackage",  // demangled-name style input
      "s:SZ",  // unresolved stdlib substitution
      "s:So8NSObjectC",  // ObjC class substitution outside the corpus
      "s:16MiniSwiftPackage7GreeterVx",  // tail begins mid-type-mangling
      "s:16MiniSwiftPackage7GreeterVy",  // signature-only tail without name
    ]
    for usr in adversarial {
      #expect(USRSymbolParser.parse(usr) == nil, "adversarial USR must parse to nil: \(usr)")
    }
  }

  @Test("the D-06 fallback counter surfaces counts and capped examples in diagnostics")
  func fallbackCounterIsObservable() {
    let diagnostics = SymbolMappingDiagnostics()
    #expect(diagnostics.summary == nil, "an all-canonical run is silent")

    for i in 0..<7 {
      diagnostics.recordFallback(usr: "s:unparseable\(i)")
    }
    #expect(diagnostics.fallbackCount == 7)
    let summary = try! #require(diagnostics.summary)
    #expect(summary.hasPrefix("7 symbol(s) emitted via the raw-USR fallback"))
    #expect(summary.contains("s:unparseable0"))
    #expect(summary.contains("s:unparseable4"))
    #expect(!summary.contains("s:unparseable5"), "examples cap at five entries")
  }
}
