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
