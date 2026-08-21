import IndexStoreDB

/// Requirement: IndexStoreDB to SCIP protobuf conversion — relationship mapping (META-01).
///
/// Maps IndexStoreDB `SymbolRelation` entries to SCIP `Scip_Relationship` messages.
///
/// Store model (04-RESEARCH Q1, reconciling the META-06 spike): type-DEFINITION
/// occurrences carry zero relations for Swift, but member occurrences (methods,
/// properties, initializers) carry `.overrideOf`, and each conformance/inheritance
/// CLAUSE reference occurrence (`class Dog: Animal`, `extension X: P`) carries a
/// pairing `SymbolRelation` (`.baseOf` / `.extendedBy`) naming the derived entity.
/// The relation roles relevant here:
///   - `.overrideOf` — witness/override member → protocol requirement or superclass
///     member (maps to is_reference + is_implementation)
///   - `.baseOf` / `.extendedBy` — clause-reference pairings; NOT harvested into
///     relationships yet (type-level `is_implementation` edges are 04-02 work)
///   - `.childOf` — member → containing type (used for enclosing_symbol, NOT relationships)
///
/// The emitted witness baseline is proven both directions by the `RelationshipParity`
/// suite (`Tests/scip-swiftTests/RelationshipParityTests.swift`) against the committed
/// `Fixtures/HierarchiesFixture/relationship-table.json` golden (D-24). This mapping is
/// frozen byte-stable — Phase-4 work EXTENDS the expected edge set, never rewrites it.
enum RelationshipMapping {
  static func scipRelationships(
    for relations: [SymbolRelation],
    symbolFormatter: (Symbol) -> String
  ) -> [Scip_Relationship] {
    relations.compactMap { relation in
      if relation.roles.contains(.childOf) {
        return nil
      }

      var rel = Scip_Relationship()
      rel.symbol = symbolFormatter(relation.symbol)

      if relation.roles.contains(.overrideOf) {
        rel.isReference = true
        rel.isImplementation = true
      }

      if !rel.isReference && !rel.isImplementation && !rel.isTypeDefinition && !rel.isDefinition {
        return nil
      }

      return rel
    }
  }
}
