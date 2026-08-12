import Foundation

/// Requirement: CROSS-04, CROSS-05 — merge multiple Scip_Index protobufs into one.
///
/// Pure protobuf manipulation: concatenate documents (with path prefixing to prevent
/// duplicate-document warnings), deduplicate external symbols, and strip external
/// symbols that are now defined in any merged document.
enum ScipIndexMerger {
  static func merge(_ indexes: [Scip_Index], repoIdentifiers: [String] = [], projectRoot: String) -> Scip_Index {
    var merged = Scip_Index()

    if let first = indexes.first {
      merged.metadata = first.metadata
    }
    merged.metadata.projectRoot = URL(fileURLWithPath: projectRoot, isDirectory: true).absoluteString

    for (index, repoId) in zip(indexes, repoIdentifiers.isEmpty ? Array(repeating: "", count: indexes.count) : repoIdentifiers) {
      for var doc in index.documents {
        if !repoId.isEmpty {
          doc.relativePath = "\(repoId)/\(doc.relativePath)"
        }
        merged.documents.append(doc)
      }
    }

    var definedSymbols = Set<String>()
    for doc in merged.documents {
      definedSymbols.formUnion(doc.symbols.map(\.symbol))
    }

    var seenExternals: [String: Scip_SymbolInformation] = [:]
    for index in indexes {
      for external in index.externalSymbols {
        if definedSymbols.contains(external.symbol) { continue }
        if seenExternals[external.symbol] == nil {
          seenExternals[external.symbol] = external
        }
      }
    }
    merged.externalSymbols = seenExternals.values.sorted { $0.symbol < $1.symbol }

    return merged
  }
}
