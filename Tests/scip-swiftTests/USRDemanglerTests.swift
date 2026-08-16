import Testing

@testable import scip_swift

/// Requirement: SYMBOL-01/SYMBOL-02 — the verified USR demangling corpus and the never-throw,
/// never-empty fallback contract. Corpus strings were verified empirically against the pinned
/// Swift 6.2.4 toolchain's `swift_demangle_getDemangledName` (07-RESEARCH.md §Key Verified
/// Facts).
@Suite("USRDemanglerTests")
struct USRDemanglerTests {
  @Test("corpus: struct USR demangles to module-qualified type name")
  func corpusStruct() throws {
    let demangler = try #require(USRDemangler.load())
    #expect(demangler.demangledDisplayName(usr: "s:16MiniSwiftPackage7GreeterV") == "MiniSwiftPackage.Greeter")
  }

  @Test("corpus: method USR demangles to full signature")
  func corpusMethod() throws {
    let demangler = try #require(USRDemangler.load())
    #expect(
      demangler.demangledDisplayName(usr: "s:16MiniSwiftPackage7GreeterV5greetSSyF")
        == "MiniSwiftPackage.Greeter.greet() -> Swift.String"
    )
  }

  @Test("corpus: initializer USR demangles to init(name:) signature")
  func corpusInitializer() throws {
    let demangler = try #require(USRDemangler.load())
    #expect(
      demangler.demangledDisplayName(usr: "s:16MiniSwiftPackage7GreeterV4nameACSS_tcfc")
        == "MiniSwiftPackage.Greeter.init(name: Swift.String) -> MiniSwiftPackage.Greeter"
    )
  }

  @Test("corpus: property getter USR demangles to accessor form")
  func corpusGetter() throws {
    let demangler = try #require(USRDemangler.load())
    #expect(
      demangler.demangledDisplayName(usr: "s:16MiniSwiftPackage7GreeterV4nameSSvg")
        == "MiniSwiftPackage.Greeter.name.getter : Swift.String"
    )
  }

  @Test("corpus: bare stdlib type USR demangles to module-qualified name")
  func corpusStdlibType() throws {
    let demangler = try #require(USRDemangler.load())
    #expect(demangler.demangledDisplayName(usr: "s:SS") == "Swift.String")
  }

  @Test("corpus: stdlib extension member demangles with module qualifier")
  func corpusStdlibMember() throws {
    let demangler = try #require(USRDemangler.load())
    #expect(demangler.demangledDisplayName(usr: "s:SS5countSivg") == "Swift.String.count.getter : Swift.Int")
  }

  @Test("fallback: non-Swift ObjC USR returns nil")
  func fallbackObjC() throws {
    let demangler = try #require(USRDemangler.load())
    #expect(demangler.demangledDisplayName(usr: "c:objc(cs)NSObject") == nil)
  }

  @Test("fallback: non-Swift C function USR returns nil")
  func fallbackCFunction() throws {
    let demangler = try #require(USRDemangler.load())
    #expect(demangler.demangledDisplayName(usr: "c:@F@printf") == nil)
  }

  @Test("fallback: closure-mangled Swift USR returns nil")
  func fallbackClosure() throws {
    let demangler = try #require(USRDemangler.load())
    #expect(demangler.demangledDisplayName(usr: "s:4null5greetyyFyS2ScfU_") == nil)
  }

  @Test("fallback: local-decl-suffix Swift USR returns nil")
  func fallbackLocalDecl() throws {
    let demangler = try #require(USRDemangler.load())
    #expect(demangler.demangledDisplayName(usr: "s:4null5outer5inneryyFyyxlF") == nil)
  }

  @Test("fallback: garbage s:-prefixed input returns nil")
  func fallbackGarbage() throws {
    let demangler = try #require(USRDemangler.load())
    #expect(demangler.demangledDisplayName(usr: "s:garbage") == nil)
  }

  @Test("fallback: empty input returns nil")
  func fallbackEmpty() throws {
    let demangler = try #require(USRDemangler.load())
    #expect(demangler.demangledDisplayName(usr: "") == nil)
  }

  @Test("truncation: init USR returns its full output past the 64-byte initial buffer")
  func truncationRetryReturnsFullString() throws {
    let demangler = try #require(USRDemangler.load())
    #expect(
      demangler.demangledDisplayName(usr: "s:16MiniSwiftPackage7GreeterV4nameACSS_tcfc")
        == "MiniSwiftPackage.Greeter.init(name: Swift.String) -> MiniSwiftPackage.Greeter"
    )
  }

  @Test("fail-soft: missing dylib yields a nil instance")
  func failSoftMissingDylib() {
    #expect(USRDemangler(dylibPath: "/nonexistent/libswiftDemangle.dylib") == nil)
  }

  @Test("determinism: repeated calls for the same USR return identical results")
  func determinism() throws {
    let demangler = try #require(USRDemangler.load())
    let first = demangler.demangledDisplayName(usr: "s:16MiniSwiftPackage7GreeterV5greetSSyF")
    let second = demangler.demangledDisplayName(usr: "s:16MiniSwiftPackage7GreeterV5greetSSyF")
    #expect(first == second)
    #expect(first == "MiniSwiftPackage.Greeter.greet() -> Swift.String")
  }
}
