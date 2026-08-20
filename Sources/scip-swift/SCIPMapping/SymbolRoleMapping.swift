import IndexStoreDB

/// Requirement: IndexStoreDB to SCIP protobuf conversion — role mapping (META-03).
///
/// Maps IndexStoreDB `SymbolRole` bits to SCIP `SymbolRole` bits. Also maps
/// `SymbolProperty.unitTest` to SCIP's `Test` role and `.declaration` to
/// `ForwardDefinition`.
///
/// See design.md Decision 3's "Correction" note: real `scip.proto`'s `SymbolRole` enum has no
/// call-specific bit, so `.call` contributes nothing beyond whatever `.reference`/`.write` already
/// produce.
///
/// FROZEN CONTRACT (D-16, 03-01): the access-bit precedence is write > read/reference >
/// no access bit — `.write` emits WriteAccess; else `.reference` or `.read` emits
/// ReadAccess; else no access bit (definitions and declarations carry
/// definition/forward-definition bits only). The store's `.call`, `.dynamic`, and
/// `.addressOf` contribute nothing to access bits, and there is deliberately no
/// default-Read for role-less occurrences (it would corrupt findReferences filtering).
/// `RoleParityTests` — plus the committed `Fixtures/SchemeFixture/role-table.json`
/// golden, regenerable with `UPDATE_ROLE_TABLE=1` — is this contract's oracle: it
/// proves every occurrence family over the SchemeFixture corpus in both directions.
/// Do not change this precedence without updating that oracle and bumping
/// `SymbolFormatVersion`.
enum SymbolRoleMapping {
  static func scipRoles(for indexStoreRoles: SymbolRole, symbol: Symbol) -> Int32 {
    var roles: Int32 = 0
    if indexStoreRoles.contains(.definition) {
      roles |= Int32(Scip_SymbolRole.definition.rawValue)
    }
    if indexStoreRoles.contains(.write) {
      roles |= Int32(Scip_SymbolRole.writeAccess.rawValue)
    } else if indexStoreRoles.contains(.reference) || indexStoreRoles.contains(.read) {
      roles |= Int32(Scip_SymbolRole.readAccess.rawValue)
    }
    if indexStoreRoles.contains(.declaration) && !indexStoreRoles.contains(.definition) {
      roles |= Int32(Scip_SymbolRole.forwardDefinition.rawValue)
    }
    if symbol.properties.contains(.unitTest) {
      roles |= Int32(Scip_SymbolRole.test.rawValue)
    }
    return roles
  }

  static func scipRoles(for indexStoreRoles: SymbolRole) -> Int32 {
    scipRoles(for: indexStoreRoles, symbol: Symbol(usr: "", name: "", kind: .unknown, language: .swift))
  }
}
