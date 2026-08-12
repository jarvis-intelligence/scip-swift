import IndexStoreDB
import Testing

@testable import scip_swift

@Suite("SymbolRoleMapping")
struct SymbolRoleMappingTests {
  @Test(".definition maps to SCIP Definition")
  func definitionRole() {
    let roles = SymbolRoleMapping.scipRoles(for: .definition, symbol: makeSymbol())
    #expect(roles == Int32(Scip_SymbolRole.definition.rawValue))
  }

  @Test(".write maps to SCIP WriteAccess")
  func writeRole() {
    let roles = SymbolRoleMapping.scipRoles(for: .write, symbol: makeSymbol())
    #expect(roles == Int32(Scip_SymbolRole.writeAccess.rawValue))
  }

  @Test(".reference (without .write) maps to SCIP ReadAccess")
  func referenceRole() {
    let roles = SymbolRoleMapping.scipRoles(for: .reference, symbol: makeSymbol())
    #expect(roles == Int32(Scip_SymbolRole.readAccess.rawValue))
  }

  @Test(".read (without .write) also maps to SCIP ReadAccess")
  func readRole() {
    let roles = SymbolRoleMapping.scipRoles(for: .read, symbol: makeSymbol())
    #expect(roles == Int32(Scip_SymbolRole.readAccess.rawValue))
  }

  @Test(".reference and .write together prefer WriteAccess, not both bits")
  func referenceAndWritePrefersWrite() {
    let roles = SymbolRoleMapping.scipRoles(for: [.reference, .write], symbol: makeSymbol())
    #expect(roles == Int32(Scip_SymbolRole.writeAccess.rawValue))
  }

  @Test(".call contributes no dedicated bit — real scip.proto has none — and rides along on .reference")
  func callRoleRidesAlongOnReference() {
    let callOnly = SymbolRoleMapping.scipRoles(for: .call, symbol: makeSymbol())
    #expect(callOnly == 0)

    let callWithReference = SymbolRoleMapping.scipRoles(for: [.call, .reference], symbol: makeSymbol())
    #expect(callWithReference == Int32(Scip_SymbolRole.readAccess.rawValue))
  }

  @Test(".definition and .call together still set Definition")
  func definitionAndCall() {
    let roles = SymbolRoleMapping.scipRoles(for: [.definition, .call], symbol: makeSymbol())
    #expect(roles == Int32(Scip_SymbolRole.definition.rawValue))
  }

  @Test("no roles maps to zero")
  func noRoles() {
    #expect(SymbolRoleMapping.scipRoles(for: [], symbol: makeSymbol()) == 0)
  }

  @Test(".declaration without .definition maps to ForwardDefinition")
  func declarationMapsToForwardDefinition() {
    let roles = SymbolRoleMapping.scipRoles(for: .declaration, symbol: makeSymbol())
    #expect(roles == Int32(Scip_SymbolRole.forwardDefinition.rawValue))
  }

  @Test(".declaration AND .definition together sets only Definition (collision guard)")
  func declarationAndDefinitionCollisionGuard() {
    let roles = SymbolRoleMapping.scipRoles(for: [.declaration, .definition], symbol: makeSymbol())
    #expect(roles == Int32(Scip_SymbolRole.definition.rawValue))
    #expect((roles & Int32(Scip_SymbolRole.forwardDefinition.rawValue)) == 0)
  }

  @Test("SymbolProperty.unitTest sets Test bit")
  func unitTestSetsTestBit() {
    let testSymbol = makeSymbol(properties: .unitTest)
    let roles = SymbolRoleMapping.scipRoles(for: .definition, symbol: testSymbol)
    #expect((roles & Int32(Scip_SymbolRole.test.rawValue)) != 0)
    #expect((roles & Int32(Scip_SymbolRole.definition.rawValue)) != 0)
  }

  @Test("non-unitTest symbol does not get Test bit")
  func nonUnitTestNoTestBit() {
    let roles = SymbolRoleMapping.scipRoles(for: .definition, symbol: makeSymbol())
    #expect((roles & Int32(Scip_SymbolRole.test.rawValue)) == 0)
  }

  private func makeSymbol(properties: SymbolProperty = SymbolProperty()) -> Symbol {
    Symbol(usr: "s:fake", name: "fake", kind: .function, subKind: .none, properties: properties, language: .swift)
  }
}
