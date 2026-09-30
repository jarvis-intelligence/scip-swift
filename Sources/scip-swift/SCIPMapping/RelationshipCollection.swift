import IndexStoreDB

extension SCIPIndexBuilder {
  /// Witness relations can live on non-definition occurrences at extension anchors,
  /// including in other files. Collect by compiler identity before emitting any document.
  func collectRelationships(
    indexStoreDB: IndexStoreDB, overloadTable: OverloadTable,
    identityTable: SymbolIdentityTable
  ) -> [String: [Scip_Relationship]] {
    var byUSR: [String: [Scip_Relationship]] = [:]
    for path in SwiftFileDiscovery.swiftFiles(underRepoPath: repoPath) {
      for occurrence in indexStoreDB.symbolOccurrences(inFilePath: path)
      where !occurrence.symbol.properties.contains(.local) {
        // Clause pairings point from the base reference to the derived type. Upstream's
        // document harvest owns their inversion; this pass collects only witnesses.
        let mapped = RelationshipMapping.scipRelationships(
          for: occurrence.relations.filter { $0.roles.contains(.overrideOf) }
        ) { symbol in
          canonicalSymbolString(
            for: symbol, isSystemLocation: occurrence.location.isSystem,
            locationModuleName: occurrence.location.moduleName,
            overloadIndex: overloadTable.index(forUSR: symbol.usr), identityTable: identityTable)
        }
        if !mapped.isEmpty {
          byUSR[occurrence.symbol.usr, default: []].append(contentsOf: mapped)
        }
      }
    }
    var bySymbol: [String: [Scip_Relationship]] = [:]
    for (usr, relationships) in byUSR {
      guard let symbol = identityTable.symbolsByUSR[usr] else { continue }
      bySymbol[symbol] = Self.canonicalizedRelationships(relationships)
    }
    return bySymbol
  }

  /// Refresh witness edges while preserving upstream's document-local type edges.
  /// Witnesses have both reference and implementation flags; clause edges have only
  /// implementation. No occurrence, extent, or carrier is invented here.
  static func applyRelationships(
    _ relationships: [String: [Scip_Relationship]], to document: inout Scip_Document
  ) {
    for i in document.symbols.indices where !document.symbols[i].symbol.hasPrefix("local ") {
      let retained = document.symbols[i].relationships.filter {
        !($0.isReference && $0.isImplementation)
      }
      document.symbols[i].relationships = canonicalizedRelationships(
        retained + (relationships[document.symbols[i].symbol] ?? []))
    }
  }
}
