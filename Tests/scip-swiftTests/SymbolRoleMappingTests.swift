import IndexStoreDB
import Testing

@testable import scip_swift

@Suite("SymbolRoleMapping")
struct SymbolRoleMappingTests {
  @Test(".definition maps to SCIP Definition")
  func definitionRole() {
    let roles = SymbolRoleMapping.scipRoles(for: .definition)
    #expect(roles == Int32(Scip_SymbolRole.definition.rawValue))
  }

  @Test(".write maps to SCIP WriteAccess")
  func writeRole() {
    let roles = SymbolRoleMapping.scipRoles(for: .write)
    #expect(roles == Int32(Scip_SymbolRole.writeAccess.rawValue))
  }

  @Test(".reference (without .write) maps to SCIP ReadAccess")
  func referenceRole() {
    let roles = SymbolRoleMapping.scipRoles(for: .reference)
    #expect(roles == Int32(Scip_SymbolRole.readAccess.rawValue))
  }

  @Test(".read (without .write) also maps to SCIP ReadAccess")
  func readRole() {
    let roles = SymbolRoleMapping.scipRoles(for: .read)
    #expect(roles == Int32(Scip_SymbolRole.readAccess.rawValue))
  }

  @Test(".reference and .write together prefer WriteAccess, not both bits")
  func referenceAndWritePrefersWrite() {
    let roles = SymbolRoleMapping.scipRoles(for: [.reference, .write])
    #expect(roles == Int32(Scip_SymbolRole.writeAccess.rawValue))
  }

  @Test(".call contributes no dedicated bit — real scip.proto has none — and rides along on .reference")
  func callRoleRidesAlongOnReference() {
    let callOnly = SymbolRoleMapping.scipRoles(for: .call)
    #expect(callOnly == 0)

    let callWithReference = SymbolRoleMapping.scipRoles(for: [.call, .reference])
    #expect(callWithReference == Int32(Scip_SymbolRole.readAccess.rawValue))
  }

  @Test(".definition and .call together still set Definition")
  func definitionAndCall() {
    let roles = SymbolRoleMapping.scipRoles(for: [.definition, .call])
    #expect(roles == Int32(Scip_SymbolRole.definition.rawValue))
  }

  @Test("no roles maps to zero")
  func noRoles() {
    #expect(SymbolRoleMapping.scipRoles(for: []) == 0)
  }
}
