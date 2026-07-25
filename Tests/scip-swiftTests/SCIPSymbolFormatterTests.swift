import Testing

@testable import scip_swift

@Suite("SCIPSymbolFormatter")
struct SCIPSymbolFormatterTests {
  @Test("real Swift USRs contain ':' (not an identifier character), so they're backtick-escaped")
  func realUSRIsEscaped() {
    let symbol = SCIPSymbolFormatter.globalSymbolString(
      packageManager: "swiftpm",
      moduleName: "MiniSwiftPackage",
      usr: "s:16MiniSwiftPackage7GreeterV"
    )
    #expect(symbol == "scip-swift swiftpm MiniSwiftPackage . `s:16MiniSwiftPackage7GreeterV`.")
  }

  @Test("a USR-shaped string using only identifier characters is used as-is")
  func identifierOnlyStringIsUnescaped() {
    let symbol = SCIPSymbolFormatter.globalSymbolString(
      packageManager: "swiftpm",
      moduleName: "MiniSwiftPackage",
      usr: "abc123"
    )
    #expect(symbol == "scip-swift swiftpm MiniSwiftPackage . abc123.")
  }

  @Test("USR containing identifier-breaking characters is backtick-escaped")
  func nonIdentifierUSR() {
    // Swift USRs commonly contain characters outside the SCIP <identifier-character> set
    // (e.g. '@', '$'-adjacent punctuation from operators); this one uses '@' as a stand-in.
    let escaped = SCIPSymbolFormatter.escapeIdentifierName("s:foo@bar")
    #expect(escaped == "`s:foo@bar`")
  }

  @Test("backticks inside an escaped identifier are doubled")
  func backtickDoubling() {
    let escaped = SCIPSymbolFormatter.escapeIdentifierName("has`backtick")
    #expect(escaped == "`has``backtick`")
  }

  @Test("empty manager/package-name/version fields use the '.' placeholder")
  func emptyFieldPlaceholder() {
    #expect(SCIPSymbolFormatter.escapeSpaceField("") == ".")
  }

  @Test("spaces in scheme/manager/package-name/version fields are doubled")
  func spaceDoubling() {
    #expect(SCIPSymbolFormatter.escapeSpaceField("has space") == "has  space")
  }

  @Test("local symbols use SCIP's bare 'local <n>' grammar")
  func localSymbolFormat() {
    #expect(SCIPSymbolFormatter.localSymbolString(localID: 0) == "local 0")
    #expect(SCIPSymbolFormatter.localSymbolString(localID: 3) == "local 3")
  }

  @Test("LocalSymbolNumberer assigns stable per-USR IDs, increasing on first sight")
  func localSymbolNumbererStability() {
    var numberer = LocalSymbolNumberer()
    let first = numberer.id(forUSR: "usr-a")
    let second = numberer.id(forUSR: "usr-b")
    let firstAgain = numberer.id(forUSR: "usr-a")

    #expect(first == 0)
    #expect(second == 1)
    #expect(firstAgain == first)
  }
}
