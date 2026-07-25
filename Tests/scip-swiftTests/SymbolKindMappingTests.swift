import IndexStoreDB
import Testing

@testable import scip_swift

@Suite("SymbolKindMapping")
struct SymbolKindMappingTests {
  private func makeSymbol(
    kind: IndexSymbolKind,
    subKind: IndexSymbolSubKind = .none
  ) -> Symbol {
    Symbol(usr: "s:fake", name: "fake", kind: kind, subKind: subKind, language: .swift)
  }

  @Test("class/struct/enum/protocol/extension map to their SCIP counterparts")
  func nominalTypes() {
    #expect(SymbolKindMapping.scipKind(for: makeSymbol(kind: .class)) == .class)
    #expect(SymbolKindMapping.scipKind(for: makeSymbol(kind: .struct)) == .struct)
    #expect(SymbolKindMapping.scipKind(for: makeSymbol(kind: .enum)) == .enum)
    #expect(SymbolKindMapping.scipKind(for: makeSymbol(kind: .protocol)) == .protocol)
    #expect(SymbolKindMapping.scipKind(for: makeSymbol(kind: .extension)) == .extension)
  }

  @Test("instance method maps to method; class/static methods map to staticMethod")
  func methods() {
    #expect(SymbolKindMapping.scipKind(for: makeSymbol(kind: .instanceMethod)) == .method)
    #expect(SymbolKindMapping.scipKind(for: makeSymbol(kind: .classMethod)) == .staticMethod)
    #expect(SymbolKindMapping.scipKind(for: makeSymbol(kind: .staticMethod)) == .staticMethod)
  }

  @Test("subKind .swiftSubscript overrides the primary kind to Subscript")
  func subscriptOverride() {
    let symbol = makeSymbol(kind: .instanceMethod, subKind: .swiftSubscript)
    #expect(SymbolKindMapping.scipKind(for: symbol) == .subscript)
  }

  @Test("accessor subKinds map to Getter/Setter")
  func accessorSubKinds() {
    #expect(SymbolKindMapping.scipKind(for: makeSymbol(kind: .instanceMethod, subKind: .accessorGetter)) == .getter)
    #expect(SymbolKindMapping.scipKind(for: makeSymbol(kind: .instanceMethod, subKind: .accessorSetter)) == .setter)
    #expect(
      SymbolKindMapping.scipKind(for: makeSymbol(kind: .instanceMethod, subKind: .swiftAccessorWillSet)) == .setter
    )
  }

  @Test("kinds with no SCIP counterpart fall back to unspecifiedKind")
  func noCounterpart() {
    #expect(SymbolKindMapping.scipKind(for: makeSymbol(kind: .unknown)) == .unspecifiedKind)
    #expect(SymbolKindMapping.scipKind(for: makeSymbol(kind: .using)) == .unspecifiedKind)
    #expect(SymbolKindMapping.scipKind(for: makeSymbol(kind: .commentTag)) == .unspecifiedKind)
  }

  @Test("destructor and conversionFunction fall back to method")
  func destructorAndConversion() {
    #expect(SymbolKindMapping.scipKind(for: makeSymbol(kind: .destructor)) == .method)
    #expect(SymbolKindMapping.scipKind(for: makeSymbol(kind: .conversionFunction)) == .method)
  }
}
