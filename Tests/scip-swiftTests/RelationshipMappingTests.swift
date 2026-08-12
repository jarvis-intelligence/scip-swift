import IndexStoreDB
import Testing

@testable import scip_swift

@Suite("RelationshipMapping")
struct RelationshipMappingTests {
  @Test("overrideOf maps to isReference and isImplementation")
  func overrideOfMaps() {
    let relations = [makeRelation(name: "baseMethod", usr: "s:base", roles: .overrideOf)]
    let result = RelationshipMapping.scipRelationships(for: relations, symbolFormatter: makeFormatter())
    #expect(result.count == 1)
    #expect(result[0].isReference == true)
    #expect(result[0].isImplementation == true)
  }

  @Test("childOf is excluded — no Relationship emitted")
  func childOfExcluded() {
    let relations = [makeRelation(name: "Container", usr: "s:container", roles: .childOf)]
    let result = RelationshipMapping.scipRelationships(for: relations, symbolFormatter: makeFormatter())
    #expect(result.isEmpty)
  }

  @Test("empty relations returns empty array")
  func emptyRelations() {
    let result = RelationshipMapping.scipRelationships(for: [], symbolFormatter: makeFormatter())
    #expect(result.isEmpty)
  }

  @Test("mixed childOf and overrideOf produces one Relationship")
  func mixedRelations() {
    let relations = [
      makeRelation(name: "Container", usr: "s:container", roles: .childOf),
      makeRelation(name: "baseMethod", usr: "s:base", roles: .overrideOf),
    ]
    let result = RelationshipMapping.scipRelationships(for: relations, symbolFormatter: makeFormatter())
    #expect(result.count == 1)
    #expect(result[0].isReference == true)
  }

  @Test("symbolFormatter is applied to relation symbol")
  func formatterApplied() {
    let relations = [makeRelation(name: "base", usr: "s:Base", roles: .overrideOf)]
    let result = RelationshipMapping.scipRelationships(for: relations) { symbol in
      "formatted \(symbol.usr)"
    }
    #expect(result.count == 1)
    #expect(result[0].symbol == "formatted s:Base")
  }

  private func makeRelation(name: String, usr: String, roles: SymbolRole) -> SymbolRelation {
    SymbolRelation(
      symbol: Symbol(usr: usr, name: name, kind: .instanceMethod, subKind: .none, language: .swift),
      roles: roles
    )
  }

  private func makeFormatter() -> (Symbol) -> String {
    { symbol in "scip-swift test Module . `\(symbol.usr)`." }
  }
}
