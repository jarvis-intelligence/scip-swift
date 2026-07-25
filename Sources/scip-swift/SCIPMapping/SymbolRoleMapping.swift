import IndexStoreDB

/// Requirement: IndexStoreDB to SCIP protobuf conversion — role mapping (task 3.3).
///
/// See design.md Decision 3's "Correction" note: real `scip.proto`'s `SymbolRole` enum has no
/// call-specific bit, so `.call` contributes nothing beyond whatever `.reference`/`.write` already
/// produce.
enum SymbolRoleMapping {
  static func scipRoles(for indexStoreRoles: SymbolRole) -> Int32 {
    var roles: Int32 = 0
    if indexStoreRoles.contains(.definition) {
      roles |= Int32(Scip_SymbolRole.definition.rawValue)
    }
    if indexStoreRoles.contains(.write) {
      roles |= Int32(Scip_SymbolRole.writeAccess.rawValue)
    } else if indexStoreRoles.contains(.reference) || indexStoreRoles.contains(.read) {
      roles |= Int32(Scip_SymbolRole.readAccess.rawValue)
    }
    return roles
  }
}
