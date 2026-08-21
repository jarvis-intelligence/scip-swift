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

  @Test("baseOf clause relation maps to isImplementation only (type-level edge)")
  func baseOfMapsToImplementationOnly() {
    // REL-01 / D-23 (04-02): a type-level clause edge is Find-implementations semantics
    // only (scip.proto:477-500 — Dog# has is_implementation with Animal# but NOT
    // is_reference), unlike the witness mapping's isReference+isImplementation pair.
    let relations = [
      makeRelation(name: "Circle", usr: "s:8HierCore6CircleV", roles: .baseOf)
    ]
    let result = RelationshipMapping.scipRelationships(for: relations, symbolFormatter: makeFormatter())
    #expect(result.count == 1)
    if let first = result.first {
      #expect(first.isImplementation == true)
      #expect(first.isReference == false)
      #expect(first.isTypeDefinition == false)
      #expect(first.isDefinition == false)
    }
  }

  @Test("extendedBy clause relation maps to isImplementation only (type-level edge)")
  func extendedByMapsToImplementationOnly() {
    let relations = [
      makeRelation(name: "Wheel", usr: "s:8HierCore5WheelV", roles: .extendedBy)
    ]
    let result = RelationshipMapping.scipRelationships(for: relations, symbolFormatter: makeFormatter())
    #expect(result.count == 1)
    if let first = result.first {
      #expect(first.isImplementation == true)
      #expect(first.isReference == false)
    }
  }


  @Test("mixed overrideOf and baseOf relations produce one edge each with their own flags")
  func mixedWitnessAndClauseRelations() {
    let relations = [
      makeRelation(name: "Container", usr: "s:container", roles: .childOf),
      makeRelation(name: "baseMethod", usr: "s:base", roles: .overrideOf),
      makeRelation(name: "Circle", usr: "s:derived", roles: .baseOf),
    ]
    let result = RelationshipMapping.scipRelationships(for: relations, symbolFormatter: makeFormatter())
    #expect(result.count == 2)
    let witness = result.first { $0.symbol == "formatted s:base" }
    #expect(witness?.isReference == true)
    #expect(witness?.isImplementation == true)
    let clause = result.first { $0.symbol == "formatted s:derived" }
    #expect(clause?.isReference == false)
    #expect(clause?.isImplementation == true)
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
