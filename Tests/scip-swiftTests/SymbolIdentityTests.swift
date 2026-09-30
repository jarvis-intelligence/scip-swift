import IndexStoreDB
import Testing

@testable import scip_swift

@Suite("Compiler symbol identity")
struct SymbolIdentityTests {
  @Test("private containers keep member names and unique private methods stay readable")
  func privateContext() throws {
    let usrs = [
      "s:4Demo4Rows33_9FDFC6611CE3A7DC2D18001A442C2491LLV5firstSbvp",
      "s:4Demo4Rows33_9FDFC6611CE3A7DC2D18001A442C2491LLV6secondSbvp",
      "s:4Demo6logger33_912A564A3D479FD49D33F6C0092EA616LLSivp",
      "s:4Demo6logger33_BBA9AA5C4DE8F7EF839EDA59634ADAA7LLSivp",
    ]
    for (usr, name) in zip(usrs, ["first", "second", "logger", "logger"]) {
      let parsed = try #require(USRSymbolParser.parse(usr))
      #expect(parsed.name == name)
      #expect(parsed.containers.map(\.name) == (name == "logger" ? [] : ["Rows"]))
    }
    let usr = "s:4Demo4ViewV13checkRollover33_40045E8B123456789012345678901234LLyyF"
    let parsed = try #require(USRSymbolParser.parse(usr))
    let symbol = Symbol(usr: usr, name: "checkRollover()", kind: .instanceMethod,
                        subKind: .none, language: .swift)
    #expect(USRSymbolMapper.canonicalSymbolString(
      parsed: parsed, symbol: symbol, isSystemLocation: false, toolchainVersion: "test")
      == "scip-swift swiftpm Demo . View#checkRollover().")
  }

  @Test("different extending modules cannot produce the same canonical member")
  func extensionContext() throws {
    var candidates: [SymbolIdentityTable.Candidate] = []
    for module in ["First", "Other"] {
      let usr = "s:SS5\(module)E4workyyF"
      let parsed = try #require(USRSymbolParser.parse(usr))
      let symbol = Symbol(usr: usr, name: "work()", kind: .instanceMethod,
                          subKind: .none, language: .swift)
      let canonical = try #require(USRSymbolMapper.canonicalSymbolString(
        parsed: parsed, symbol: symbol, isSystemLocation: false,
        toolchainVersion: "test"))
      #expect(canonical == "scip-swift swift Swift test String#work().")
      candidates.append(.init(usr: usr, canonical: canonical, fallback: "raw \(usr)"))
    }
    let table = SymbolIdentityTable(candidates: candidates)
    #expect(Set(table.symbolsByUSR.values).count == 2)
    // The suffix sits on the colliding descriptor's own name, keeping its Method form.
    #expect(table.symbolsByUSR.values.allSatisfy {
      $0.hasPrefix("scip-swift swift Swift test String#`work@") && $0.hasSuffix("`().")
    })
    #expect(table.fallbackUSRs.isEmpty)
  }

  @Test("inverse collisions remap every USR independent of occurrence order")
  func inverseCollisions() throws {
    let same = "scip-swift swiftpm Demo . Same#"
    let candidates: [SymbolIdentityTable.Candidate] = [
      .init(usr: "first", canonical: same, fallback: "raw first"),
      .init(usr: "second", canonical: same, fallback: "raw second"),
      .init(usr: "first", canonical: same, fallback: "raw first"),
      .init(usr: "third", canonical: "unique", fallback: "raw third"),
    ]
    let table = SymbolIdentityTable(candidates: candidates)
    #expect(Set(table.symbolsByUSR.values).count == 3)
    for usr in ["first", "second"] {
      let symbol = try #require(table.symbolsByUSR[usr])
      #expect(symbol.hasPrefix("scip-swift swiftpm Demo . `Same@") && symbol.hasSuffix("`#"))
    }
    #expect(table.symbolsByUSR["third"] == "unique")
    #expect(table.fallbackUSRs.isEmpty)
    let reversed = SymbolIdentityTable(candidates: Array(candidates.reversed()))
    #expect(reversed.symbolsByUSR == table.symbolsByUSR)
    #expect(reversed.cacheValidationFingerprint() == table.cacheValidationFingerprint())
  }

  @Test("shared discriminator prefixes and existing spellings never merge identities")
  func suffixCollisions() throws {
    let first = "s:4Demo6logger33_12345678AAAAAAAAAAAAAAAAAAAAAAAALLSivp"
    let second = "s:4Demo6logger33_12345678BBBBBBBBBBBBBBBBBBBBBBBBLLSivp"
    let canonical = "scip-swift swiftpm Demo . logger."
    let reserved = "scip-swift swiftpm Demo . `logger@12345678`."
    let candidates: [SymbolIdentityTable.Candidate] = [
      .init(usr: first, canonical: canonical, fallback: "raw first"),
      .init(usr: second, canonical: canonical, fallback: "raw second"),
      .init(usr: "reserved", canonical: reserved, fallback: "raw third"),
    ]
    let table = SymbolIdentityTable(candidates: candidates)
    #expect(Set(table.symbolsByUSR.values).count == 3)
    #expect(table.symbolsByUSR["reserved"] == reserved)
    #expect(table.symbolsByUSR == SymbolIdentityTable(candidates: candidates.reversed()).symbolsByUSR)
  }

  @Test("a fallback defined in the index takes its defining document's spelling everywhere")
  func definedFallbackUsesDefiningModule() {
    let usr = "s:4Zeta3VecVyS2icig"
    let zeta = "scip-swift swiftpm Zeta . `\(usr)`."
    let alpha = "scip-swift swiftpm Alpha . `\(usr)`."
    // The referencing module sorts first, so a lexicographic choice would pick Alpha.
    let candidates: [SymbolIdentityTable.Candidate] = [
      .init(usr: usr, canonical: alpha, fallback: alpha),
      .init(usr: usr, canonical: zeta, fallback: zeta, isDefinition: true),
    ]
    for ordered in [candidates, candidates.reversed()] {
      let table = SymbolIdentityTable(candidates: ordered)
      #expect(table.symbolsByUSR[usr] == zeta)
      #expect(table.fallbackUSRs == [usr])
    }
  }

  @Test("a fallback with no in-index definition keeps location-based attribution")
  func externalFallbackStaysLocationBased() {
    let usr = "s:10ExternalKit3BoxVyS2icig"
    let candidates: [SymbolIdentityTable.Candidate] = [
      .init(usr: usr, canonical: "scip-swift swiftpm Alpha . `\(usr)`.",
            fallback: "scip-swift swiftpm Alpha . `\(usr)`."),
      .init(usr: usr, canonical: "scip-swift swiftpm Beta . `\(usr)`.",
            fallback: "scip-swift swiftpm Beta . `\(usr)`."),
    ]
    let table = SymbolIdentityTable(candidates: candidates)
    // Absent from the table: each occurrence renders its own location's module header.
    #expect(table.symbolsByUSR[usr] == nil)
    #expect(table.fallbackUSRs.isEmpty)
  }

  @Test("colliding private types carry the suffix and their members live under it")
  func privateTypesCarryMembers() throws {
    let first = "9FDFC6611CE3A7DC2D18001A442C2491"
    let second = "40045E8B123456789012345678901234"
    let usrs = [first, second].flatMap { disc in
      [
        "s:4Demo6Marker33_\(disc)LLV",  // the type
        "s:4Demo6Marker33_\(disc)LLV5valueSivp",  // property
        "s:4Demo6Marker33_\(disc)LLV5valueSivg",  // getter
        "s:4Demo6Marker33_\(disc)LLV5touchyyF",  // method
      ]
    } + [
      "s:4Demo4Rows33_\(first)LLV5firstSbvp",  // unique private type: stays readable
      "s:4Demo6logger33_\(first)LLSivp", "s:4Demo6logger33_\(first)LLSivg",
      "s:4Demo6logger33_\(second)LLSivp",
    ]
    let parsed = try usrs.map { try #require(USRSymbolParser.parse($0)) }
    let table = PrivateContextTable(parsed: parsed)
    let applied = parsed.map(table.apply)
    let markerNames = applied.prefix(8).map { ($0.containers.map(\.name) + [$0.name]) }
    for (index, names) in markerNames.enumerated() {
      let expected = index < 4 ? "Marker@9FDFC661" : "Marker@40045E8B"
      #expect(names.first == expected, "\(usrs[index]) -> \(names)")
    }
    #expect(applied[8].containers.map(\.name) == ["Rows"])
    #expect(applied[8].name == "first")
    // A var and its accessor share one suffix; the other file's logger gets its own.
    #expect(applied[9].name == "logger@9FDFC661")
    #expect(applied[10].name == "logger@9FDFC661")
    #expect(applied[11].name == "logger@40045E8B")

    let symbol = Symbol(usr: usrs[1], name: "value", kind: .instanceProperty,
                        subKind: .none, language: .swift)
    #expect(USRSymbolMapper.canonicalSymbolString(
      parsed: applied[1], symbol: symbol, isSystemLocation: false, toolchainVersion: "test")
      == "scip-swift swiftpm Demo . `Marker@9FDFC661`#value.")
  }

  @Test("renaming a descriptor keeps its kind suffix and escapes the new name")
  func renamingLastDescriptor() {
    let cases: [(String, String)] = [
      ("h . Marker#", "h . `Marker@1`#"),
      ("h . Box#value.", "h . Box#`value@1`."),
      ("h . Box#work(+2).", "h . Box#`work@1`(+2)."),
      ("h . Box#`value=`().", "h . Box#`value=@1`()."),
      ("h . Box#`a``b`.", "h . Box#`a``b@1`."),
      ("h . M/", "h . `M@1`/"),
    ]
    for (symbol, expected) in cases {
      #expect(SymbolIdentityTable.renamingLastDescriptor(of: symbol, suffix: "@1") == expected)
    }
  }
}
