import Testing

@testable import scip_swift

@Suite("Word substitutions")
struct WordSubstitutionTests {
  @Test("literal and substituted words retain the source identifier and context")
  func substitutedIdentifiers() {
    // ABI identifier productions: literal before reference, multiple references,
    // final literal or zero, and words introduced earlier in the SAME identifier.
    let cases: [(String, String, [String])] = [
      ("s:8ProbeKit15RolloverServiceO07performC8IfNeededyyF",
       "performRolloverIfNeeded", ["RolloverService"]),
      ("s:9AbcDefGHI02Myac1_B0yyF", "MyAbcGHI_Def", []),
      ("s:4Test03FooB0yyF", "FooFoo", []),
      ("s:4Test10AlphaOmegaV0bC0yyF", "AlphaOmega", ["AlphaOmega"]),
      ("s:4Test10AlphaOmegaV0B4TailyyF", "AlphaTail", ["AlphaOmega"]),
      // E is a valid word index here but MUST remain the extension marker.
      ("s:13SchemeFixture12BoxExtraTypeV0aB3ExtE8describeSSyF",
       "describe", ["BoxExtraType"]),
      // A single letter and a leading digit run do not occupy word-table entries.
      ("s:4Test8A_Beta2CV0B0yyF", "Beta2", ["A_Beta2C"]),
      ("s:4Test8_12AlphaV0B0yyF", "Alpha", ["_12Alpha"]),
      // Do not register the assembled FooFoo as another word before reading Bar.
      ("s:4Test03FooB0V3BarV0C0yyF", "Bar", ["FooFoo", "Bar"]),
    ]
    for (usr, name, containers) in cases {
      let result = USRSymbolParser.parse(usr)
      #expect(result != nil, "\(usr)")
      guard let parsed = result else { continue }
      #expect(parsed.name == name, "\(usr)")
      #expect(parsed.containers.map(\.name) == containers, "\(usr)")
    }
  }

  @Test("invalid word references and incomplete substitutions fail closed")
  func malformedSubstitutions() {
    for tail in ["0Z0", "0zA0", "0A", "0A99short", "03Foo", "0a"] {
      #expect(USRSymbolParser.parse("s:4Test" + tail) == nil, "\(tail)")
    }
    // Punycode identifiers do not add substitution words.
    #expect(USRSymbolParser.parse("s:4Test004BFIhV0B0yyF") == nil)
  }

  @Test("word substitutions retain their indices when the 26-word table is full")
  func fullWordTable() throws {
    let words = (0..<26).map { "Word\($0)" }.joined(separator: "_")
    let parsed = try #require(USRSymbolParser.parse("s:\(words.count)\(words)0Z0yyF"))
    #expect(parsed.name == "Word25")
  }
}
