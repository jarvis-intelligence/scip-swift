import IndexStoreDB
import Testing

@testable import scip_swift

@Suite("SignatureMapping")
struct SignatureMappingTests {
  @Test("function produces 'func <name>'")
  func functionSignature() {
    let sig = SignatureMapping.signature(for: makeSymbol(kind: .function, name: "greet"))
    #expect(sig?.text == "func greet")
    #expect(sig?.language == "swift")
  }

  @Test("instanceMethod produces 'func <name>'")
  func instanceMethodSignature() {
    let sig = SignatureMapping.signature(for: makeSymbol(kind: .instanceMethod, name: "greet(name:)"))
    #expect(sig?.text == "func greet(name:)")
  }

  @Test("classMethod produces 'static func <name>'")
  func classMethodSignature() {
    let sig = SignatureMapping.signature(for: makeSymbol(kind: .classMethod, name: "create()"))
    #expect(sig?.text == "static func create()")
  }

  @Test("instanceProperty produces 'var <name>'")
  func instancePropertySignature() {
    let sig = SignatureMapping.signature(for: makeSymbol(kind: .instanceProperty, name: "name"))
    #expect(sig?.text == "var name")
  }

  @Test("classProperty produces 'static var <name>'")
  func classPropertySignature() {
    let sig = SignatureMapping.signature(for: makeSymbol(kind: .classProperty, name: "count"))
    #expect(sig?.text == "static var count")
  }

  @Test("class produces 'class <name>'")
  func classSignature() {
    let sig = SignatureMapping.signature(for: makeSymbol(kind: .class, name: "Greeter"))
    #expect(sig?.text == "class Greeter")
  }

  @Test("struct produces 'struct <name>'")
  func structSignature() {
    let sig = SignatureMapping.signature(for: makeSymbol(kind: .struct, name: "Point"))
    #expect(sig?.text == "struct Point")
  }

  @Test("enum produces 'enum <name>'")
  func enumSignature() {
    let sig = SignatureMapping.signature(for: makeSymbol(kind: .enum, name: "Color"))
    #expect(sig?.text == "enum Color")
  }

  @Test("protocol produces 'protocol <name>'")
  func protocolSignature() {
    let sig = SignatureMapping.signature(for: makeSymbol(kind: .protocol, name: "Drawable"))
    #expect(sig?.text == "protocol Drawable")
  }

  @Test("constructor produces 'init'")
  func constructorSignature() {
    let sig = SignatureMapping.signature(for: makeSymbol(kind: .constructor, name: "init()"))
    #expect(sig?.text == "init init()")
  }

  @Test("parameter returns nil")
  func parameterReturnsNil() {
    let sig = SignatureMapping.signature(for: makeSymbol(kind: .parameter, name: "name"))
    #expect(sig == nil)
  }

  @Test("module returns nil")
  func moduleReturnsNil() {
    let sig = SignatureMapping.signature(for: makeSymbol(kind: .module, name: "Swift"))
    #expect(sig == nil)
  }

  private func makeSymbol(kind: IndexSymbolKind, name: String) -> Symbol {
    Symbol(usr: "s:fake", name: name, kind: kind, subKind: .none, language: .swift)
  }
}
