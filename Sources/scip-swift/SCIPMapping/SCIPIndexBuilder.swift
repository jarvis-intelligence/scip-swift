import Foundation
import IndexStoreDB

/// Requirement: IndexStoreDB to SCIP protobuf conversion (task 3.6) — drives the whole mapping,
/// producing a complete `Scip_Index` from an opened IndexStoreDB.
struct SCIPIndexBuilder {
  /// Absolute path to the repo root (becomes `Metadata.project_root` and the base that
  /// `Document.relative_path` is computed against).
  let repoPath: String
  let indexStorePath: String
  let databasePath: String
  /// The build backend used ("swiftpm" or "xcodebuild"), embedded in every symbol's package
  /// manager field.
  let buildToolName: String
  let converterVersion: String

  func build() throws -> Scip_Index {
    let indexStoreDB = try IndexStoreLoader.open(storePath: indexStorePath, databasePath: databasePath)

    var index = Scip_Index()
    index.metadata = makeMetadata()

    // Every non-local symbol referenced anywhere, keyed by its SCIP symbol string. Used to
    // populate `external_symbols` for symbols referenced but never defined in this index (e.g.
    // Swift standard library types) — required for the emitted index to pass `scip lint`, since
    // real `scip.proto` has no concept of "reference to an unaccounted-for symbol".
    var referencedSymbols: [String: Scip_SymbolInformation] = [:]
    var definedSymbolStrings: Set<String> = []

    for filePath in SwiftFileDiscovery.swiftFiles(underRepoPath: repoPath) {
      if let document = makeDocument(
        filePath: filePath,
        indexStoreDB: indexStoreDB,
        referencedSymbols: &referencedSymbols
      ) {
        definedSymbolStrings.formUnion(document.symbols.map(\.symbol))
        index.documents.append(document)
      }
    }

    index.externalSymbols = referencedSymbols.values
      .filter { !definedSymbolStrings.contains($0.symbol) }
      .sorted { $0.symbol < $1.symbol }

    return index
  }

  private func makeMetadata() -> Scip_Metadata {
    var toolInfo = Scip_ToolInfo()
    toolInfo.name = "scip-swift"
    toolInfo.version = converterVersion
    toolInfo.arguments = CommandLine.arguments

    var metadata = Scip_Metadata()
    metadata.toolInfo = toolInfo
    metadata.projectRoot = URL(fileURLWithPath: repoPath, isDirectory: true).absoluteString
    metadata.textDocumentEncoding = .utf8
    return metadata
  }

  private func makeDocument(
    filePath: String,
    indexStoreDB: IndexStoreDB,
    referencedSymbols: inout [String: Scip_SymbolInformation]
  ) -> Scip_Document? {
    let occurrences = indexStoreDB.symbolOccurrences(inFilePath: filePath)
    guard !occurrences.isEmpty else { return nil }

    var document = Scip_Document()
    document.language = "Swift"
    document.relativePath = relativePath(of: filePath)
    document.positionEncoding = .utf8CodeUnitOffsetFromLineStart

    var localNumberer = LocalSymbolNumberer()
    var definedSymbols: [String: Scip_SymbolInformation] = [:]

    for occurrence in occurrences.sorted() {
      let symbol = occurrence.symbol
      let isLocal = symbol.properties.contains(.local)
      let symbolString =
        isLocal
        ? SCIPSymbolFormatter.localSymbolString(localID: localNumberer.id(forUSR: symbol.usr))
        : SCIPSymbolFormatter.globalSymbolString(
          packageManager: buildToolName,
          moduleName: occurrence.location.moduleName,
          usr: symbol.usr
        )

      var scipOccurrence = Scip_Occurrence()
      scipOccurrence.symbol = symbolString
      scipOccurrence.symbolRoles = SymbolRoleMapping.scipRoles(for: occurrence.roles)
      scipOccurrence.singleLineRange = PositionMapping.singleLineRange(
        location: occurrence.location,
        displayName: symbol.name
      )
      document.occurrences.append(scipOccurrence)

      var symbolInformation = Scip_SymbolInformation()
      symbolInformation.symbol = symbolString
      symbolInformation.displayName = symbol.name
      symbolInformation.kind = SymbolKindMapping.scipKind(for: symbol)

      if occurrence.roles.contains(.definition) {
        definedSymbols[symbolString] = symbolInformation
      } else if !isLocal, referencedSymbols[symbolString] == nil {
        referencedSymbols[symbolString] = symbolInformation
      }
    }

    document.symbols = definedSymbols.values.sorted { $0.symbol < $1.symbol }
    return document
  }

  private func relativePath(of filePath: String) -> String {
    let normalizedRepoPath = repoPath.hasSuffix("/") ? repoPath : repoPath + "/"
    guard filePath.hasPrefix(normalizedRepoPath) else { return filePath }
    return String(filePath.dropFirst(normalizedRepoPath.count))
  }
}
