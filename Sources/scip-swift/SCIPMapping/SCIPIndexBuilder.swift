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

  /// Per-run D-06 fallback accounting, surfaced as a diagnostic at the end of `build()`.
  let symbolMappingDiagnostics = SymbolMappingDiagnostics()

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
          if let demangler {
            // D-06 fallback symbols still embed the raw USR in their trailing descriptor, so
            // they keep their demangled display names. Canonical descriptor chains no longer
            // embed a USR: their display name is derived deterministically from the symbol
            // string itself, so fresh and cache-served documents agree (byte-identical runs).
            if let usr = Self.usr(fromCanonicalSymbolString: sym), usr.wasFallbackForm {
              info.displayName = demangler.demangledDisplayName(usr: usr.usr) ?? ""
            } else {
              info.displayName = CanonicalSymbolFormatter.displayName(fromCanonicalString: sym)
            }
          }
          externalSymbols[sym] = info
        }
      }
    }
    index.externalSymbols = externalSymbols.values.sorted { $0.symbol < $1.symbol }

    if let fallbackSummary = symbolMappingDiagnostics.summary {
      print("warning: \(fallbackSummary)")
    }

    return index
  }

  /// Maps one IndexStoreDB symbol onto its canonical symbol string (SYM-03): parse the USR,
  /// derive module/containers/name and the module header from the USR itself — never from
  /// `location.moduleName`, which reports the declaring module for retroactive extension
  /// members — and assemble via `CanonicalSymbolFormatter`. A USR the parser cannot handle
  /// takes the D-06 raw-USR fallback under the canonical module header, recorded in the
  /// per-run diagnostics; indexing never fails or drops a symbol here.
  private func canonicalSymbolString(
    for symbol: Symbol, isSystemLocation: Bool, locationModuleName: String
  ) -> String {
    if let parsed = USRSymbolParser.parse(symbol.usr),
      let canonical = USRSymbolMapper.canonicalSymbolString(
        parsed: parsed,
        symbol: symbol,
        isSystemLocation: isSystemLocation,
        toolchainVersion: ToolchainInfo.pinnedSwiftVersion
      )
    {
      return canonical
    }
    symbolMappingDiagnostics.recordFallback(usr: symbol.usr)
    return SCIPSymbolFormatter.fallbackSymbolString(
      isSystem: isSystemLocation,
      moduleName: locationModuleName,
      toolchainVersion: ToolchainInfo.pinnedSwiftVersion,
      usr: symbol.usr
    )
  }

  /// Inverse of the D-06 fallback rendering: a raw USR rides verbatim in the trailing
  /// `` `<usr>`. `` descriptor, so it can be recovered even for documents served from cache
  /// (where no IndexStoreDB symbol is at hand). `wasFallbackForm` distinguishes that shape
  /// from a canonical Term descriptor, which never embeds a USR.
  private static func usr(
    fromCanonicalSymbolString symbolString: String
  ) -> (usr: String, wasFallbackForm: Bool)? {
    guard let separator = symbolString.lastIndex(of: " ") else { return nil }
    let descriptor = symbolString[separator...].dropFirst()
    guard descriptor.hasSuffix(".") else { return nil }
    let name = descriptor.dropLast()
    if name.hasPrefix("`"), name.hasSuffix("`") {
      return (
        String(name.dropFirst().dropLast().replacingOccurrences(of: "``", with: "`")), true
      )
    }
    return (String(name), false)
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
    let refiner = SwiftSyntaxRefiner(filePath: filePath)

    for occurrence in occurrences.sorted() {
      let symbol = occurrence.symbol
      let isLocal = symbol.properties.contains(.local)
      let symbolString =
        isLocal
        ? SCIPSymbolFormatter.localSymbolString(localID: localNumberer.id(forUSR: symbol.usr))
        : canonicalSymbolString(
          for: symbol,
          isSystemLocation: occurrence.location.isSystem,
          locationModuleName: occurrence.location.moduleName
        )

      var scipOccurrence = Scip_Occurrence()
      scipOccurrence.symbol = symbolString
      scipOccurrence.symbolRoles = SymbolRoleMapping.scipRoles(for: occurrence.roles, symbol: symbol)
      if Self.isGeneratedPath(filePath) {
        scipOccurrence.symbolRoles |= Int32(Scip_SymbolRole.generated.rawValue)
      }
      scipOccurrence.singleLineRange = PositionMapping.singleLineRange(
        location: occurrence.location,
        displayName: symbol.name,
        exactEndColumn: refiner?
          .exactEndColumn(line: occurrence.location.line, utf8Column: occurrence.location.utf8Column)
          .map(Int32.init)
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
      if occurrence.roles.contains(.definition),
        let doc = refiner?.documentation(
          line: occurrence.location.line,
          utf8Column: occurrence.location.utf8Column
        )
      {
        symbolInformation.documentation = [doc]
      }

      if isLocal, let childOfRelation = occurrence.relations.first(where: { $0.roles.contains(.childOf) }) {
        symbolInformation.enclosingSymbol = canonicalSymbolString(
          for: childOfRelation.symbol,
          isSystemLocation: occurrence.location.isSystem,
          locationModuleName: occurrence.location.moduleName
        )
      }

      if occurrence.roles.contains(.definition) {
        if !isLocal {
          symbolInformation.relationships = RelationshipMapping.scipRelationships(
            for: occurrence.relations,
            symbolFormatter: { relSymbol in
              canonicalSymbolString(
                for: relSymbol,
                isSystemLocation: occurrence.location.isSystem,
                locationModuleName: occurrence.location.moduleName
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
