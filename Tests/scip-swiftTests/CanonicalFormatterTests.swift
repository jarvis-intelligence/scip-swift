import Testing

@testable import scip_swift

/// Requirement: SYM-03 — escaping and local-form rules of the canonical formatter (the
/// single escaping implementation). Absorbs the escaping tests that lived on
/// `SCIPSymbolFormatterTests` before the Phase-2 symbol-scheme port; the raw-USR tests stay
/// there because that type now renders only the D-06 fallback.
@Suite("CanonicalFormatter")
struct CanonicalFormatterTests {
  @Test("non-identifier strings are backtick-escaped")
  func nonIdentifierName() {
    // Swift source names can contain characters outside the SCIP <identifier-character> set
    // (operators, CJK identifiers, accessors like "area="); this one uses '@' as a stand-in.
    #expect(CanonicalSymbolFormatter.escapeIdentifierName("s:foo@bar") == "`s:foo@bar`")
  }

  @Test("backticks inside an escaped identifier are doubled")
  func backtickDoubling() {
    #expect(CanonicalSymbolFormatter.escapeIdentifierName("has`backtick") == "`has``backtick`")
  }

  @Test("identifier-only strings are used as-is, including + - $ and digits")
  func identifierOnlyName() {
    #expect(CanonicalSymbolFormatter.escapeIdentifierName("abc123") == "abc123")
    #expect(CanonicalSymbolFormatter.escapeIdentifierName("+") == "+")
    #expect(CanonicalSymbolFormatter.escapeIdentifierName("_a-b$c") == "_a-b$c")
  }

  @Test("empty manager/package-name/version fields use the '.' placeholder")
  func emptyFieldPlaceholder() {
    #expect(CanonicalSymbolFormatter.escapeSpaceField("") == ".")
  }

  @Test("spaces in scheme/manager/package-name/version fields are doubled")
  func spaceDoubling() {
    #expect(CanonicalSymbolFormatter.escapeSpaceField("has space") == "has  space")
  }

  @Test("local ids sanitize non-identifier runes to '_' and append _N when ordinal > 0")
  func localSymbolSanitization() {
    #expect(CanonicalSymbolFormatter.localSymbol(sourceName: "i", ordinal: 0) == "local i")
    #expect(CanonicalSymbolFormatter.localSymbol(sourceName: "🚀", ordinal: 0) == "local _")
    #expect(CanonicalSymbolFormatter.localSymbol(sourceName: "count", ordinal: 2) == "local count_2")
    #expect(CanonicalSymbolFormatter.localSymbol(sourceName: "x", ordinal: 1) == "local x_1")
    // Unicode source names never appear raw in a local id.
    #expect(CanonicalSymbolFormatter.localSymbol(sourceName: "名前", ordinal: 0) == "local __")
  }

  @Test("derived display names decode the canonical string deterministically")
  func derivedDisplayNames() {
    #expect(
      CanonicalSymbolFormatter.displayName(fromCanonicalString: "scip-swift swift Swift 6.2.4 String#")
        == "Swift.String")
    #expect(
      CanonicalSymbolFormatter.displayName(
        fromCanonicalString: "scip-swift swiftpm MyMod . Shape#resize(+1)."
      ) == "MyMod.Shape.resize")
    #expect(
      CanonicalSymbolFormatter.displayName(fromCanonicalString: "scip-swift swiftpm MyMod . f().(x)")
        == "MyMod.f.x")
    #expect(
      CanonicalSymbolFormatter.displayName(fromCanonicalString: "scip-swift swiftpm MyMod . Box#[T]")
        == "MyMod.Box.T")
  }
}
