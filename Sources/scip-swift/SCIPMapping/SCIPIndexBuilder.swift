import Foundation
import IndexStoreDB

/// Requirement: IndexStoreDB to SCIP protobuf conversion (task 3.6) — drives the whole mapping,
/// producing a complete `Scip_Index` from an opened IndexStoreDB.
struct SCIPIndexBuilder {
  let repoPath: String
  let indexStorePath: String
  let databasePath: String
  let buildToolName: String
  let converterVersion: String
  let symbolVersion: String
  let cacheStore: CacheStore?
  let demangle: Bool

  init(
    repoPath: String,
    indexStorePath: String,
    databasePath: String,
    buildToolName: String,
    converterVersion: String,
    symbolVersion: String = "",
    cacheStore: CacheStore? = nil,
    demangle: Bool = true
  ) {
    self.repoPath = repoPath
    self.indexStorePath = indexStorePath
    self.databasePath = databasePath
    self.buildToolName = buildToolName
    self.converterVersion = converterVersion
    self.symbolVersion = symbolVersion
    self.cacheStore = cacheStore
    self.demangle = demangle
  }

  func build() throws -> Scip_Index {
    let indexStoreDB = try IndexStoreLoader.open(storePath: indexStorePath, databasePath: databasePath)
    indexStoreDB.pollForUnitChangesAndWait()

    let demangler = demangle ? USRDemangler.load() : nil

    var index = Scip_Index()
    index.metadata = makeMetadata()

    var referencedSymbols: [String: Scip_SymbolInformation] = [:]
    var systemReferencedSymbols: [String: Scip_SymbolInformation] = [:]
    var definedSymbolStrings: Set<String> = []

    for filePath in SwiftFileDiscovery.swiftFiles(underRepoPath: repoPath) {
      var document: Scip_Document?

      if let cacheStore {
        let contentHash = try? ContentHasher.sha256Hex(of: filePath)
        if let hash = contentHash {
          if let cached = cacheStore.loadDocument(hash: hash),
             indexStoreDB.dateOfLatestUnitFor(filePath: filePath) != nil {
            document = cached
          }
        }

        if document == nil {
          if let fresh = makeDocument(
            filePath: filePath,
            indexStoreDB: indexStoreDB,
            demangler: demangler,
            referencedSymbols: &referencedSymbols,
            systemReferencedSymbols: &systemReferencedSymbols
          ) {
            if let hash = contentHash {
              try? cacheStore.saveDocument(fresh, hash: hash)
            }
            document = fresh
          }
        }
      } else {
        document = makeDocument(
          filePath: filePath,
          indexStoreDB: indexStoreDB,
          demangler: demangler,
          referencedSymbols: &referencedSymbols,
          systemReferencedSymbols: &systemReferencedSymbols
        )
      }

      if let document {
        definedSymbolStrings.formUnion(document.symbols.map(\.symbol))
        index.documents.append(document)
      }
    }

    var externalSymbols: [String: Scip_SymbolInformation] = [:]
    for doc in index.documents {
      for occurrence in doc.occurrences {
        let sym = occurrence.symbol
        if !sym.hasPrefix("local ") && !definedSymbolStrings.contains(sym) && externalSymbols[sym] == nil {
          var info = Scip_SymbolInformation()
          info.symbol = sym
          if let demangler, let usr = Self.usr(fromCanonicalSymbolString: sym) {
            info.displayName = demangler.demangledDisplayName(usr: usr) ?? ""
          }
          externalSymbols[sym] = info
        }
      }
    }
    index.externalSymbols = externalSymbols.values.sorted { $0.symbol < $1.symbol }

    return index
  }

  /// Inverse of `SCIPSymbolFormatter.globalSymbolString`'s descriptor rendering: the USR rides
  /// verbatim in the trailing `` `<usr>`. `` descriptor, so it can be recovered even for
  /// documents served from cache (where no IndexStoreDB symbol is at hand).
  private static func usr(fromCanonicalSymbolString symbolString: String) -> String? {
    guard let separator = symbolString.lastIndex(of: " ") else { return nil }
    let descriptor = symbolString[separator...].dropFirst()
    guard descriptor.hasSuffix(".") else { return nil }
    let name = descriptor.dropLast()
    if name.hasPrefix("`"), name.hasSuffix("`") {
      return String(name.dropFirst().dropLast().replacingOccurrences(of: "``", with: "`"))
    }
    return String(name)
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
    demangler: USRDemangler?,
    referencedSymbols: inout [String: Scip_SymbolInformation],
    systemReferencedSymbols: inout [String: Scip_SymbolInformation]
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
          version: symbolVersion,
          usr: symbol.usr
        )

      var scipOccurrence = Scip_Occurrence()
      scipOccurrence.symbol = symbolString
      scipOccurrence.symbolRoles = SymbolRoleMapping.scipRoles(for: occurrence.roles, symbol: symbol)
      if Self.isGeneratedPath(filePath) {
        scipOccurrence.symbolRoles |= Int32(Scip_SymbolRole.generated.rawValue)
      }
      scipOccurrence.singleLineRange = PositionMapping.singleLineRange(
        location: occurrence.location,
        displayName: symbol.name
      )
      document.occurrences.append(scipOccurrence)

      var symbolInformation = Scip_SymbolInformation()
      symbolInformation.symbol = symbolString
      symbolInformation.displayName =
        isLocal ? symbol.name : (demangler?.demangledDisplayName(usr: symbol.usr) ?? symbol.name)
      symbolInformation.kind = SymbolKindMapping.scipKind(for: symbol)
      if let signature = SignatureMapping.signature(for: symbol) {
        symbolInformation.signatureDocumentation = signature
      }

      if isLocal, let childOfRelation = occurrence.relations.first(where: { $0.roles.contains(.childOf) }) {
        symbolInformation.enclosingSymbol = SCIPSymbolFormatter.globalSymbolString(
          packageManager: buildToolName,
          moduleName: occurrence.location.moduleName,
          version: symbolVersion,
          usr: childOfRelation.symbol.usr
        )
      }

      if occurrence.roles.contains(.definition) {
        if !isLocal {
          symbolInformation.relationships = RelationshipMapping.scipRelationships(
            for: occurrence.relations,
            symbolFormatter: { relSymbol in
              SCIPSymbolFormatter.globalSymbolString(
                packageManager: buildToolName,
                moduleName: occurrence.location.moduleName,
                version: symbolVersion,
                usr: relSymbol.usr
              )
            }
          )
        }
        definedSymbols[symbolString] = symbolInformation
      } else if !isLocal, referencedSymbols[symbolString] == nil, systemReferencedSymbols[symbolString] == nil {
        if occurrence.location.isSystem {
          systemReferencedSymbols[symbolString] = symbolInformation
        } else {
          referencedSymbols[symbolString] = symbolInformation
        }
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

  private static func isGeneratedPath(_ filePath: String) -> Bool {
    let generatedComponents: Set<String> = [".build", "DerivedData", ".index-build"]
    let components = filePath.split(separator: "/")
    return components.contains { generatedComponents.contains(String($0)) }
  }
}
