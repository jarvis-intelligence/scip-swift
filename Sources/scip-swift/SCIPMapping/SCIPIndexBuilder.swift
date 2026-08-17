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

    // Phase A (D-07): a light definitions pre-pass fills the USR-keyed overload table before
    // any document is emitted, so definitions and references render identical strings by
    // construction (Pitfall 4 — the lint missingSymbolForOccurrenceError contract).
    let overloadTable = buildOverloadTable(indexStoreDB: indexStoreDB)

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
            overloadTable: overloadTable,
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
          overloadTable: overloadTable,
          referencedSymbols: &referencedSymbols,
          systemReferencedSymbols: &systemReferencedSymbols
        )
      }

      if let document {
        definedSymbolStrings.formUnion(document.symbols.map(\.symbol))
        index.documents.append(document)
      }
    }

    // D-10 (02-02): documents ascend by relativePath, mirroring Go `SortDocuments`. Discovery
    // already walks in sorted order; sorting here makes the emitted contract explicit rather
    // than incidental on the directory walk.
    index.documents.sort { $0.relativePath < $1.relativePath }

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
    for symbol: Symbol, isSystemLocation: Bool, locationModuleName: String,
    overloadIndex: Int = 0
  ) -> String {
    if let parsed = USRSymbolParser.parse(symbol.usr),
      let canonical = USRSymbolMapper.canonicalSymbolString(
        parsed: parsed,
        symbol: symbol,
        isSystemLocation: isSystemLocation,
        toolchainVersion: ToolchainInfo.pinnedSwiftVersion,
        overloadIndex: overloadIndex
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

  /// Phase A of the two-phase build (D-07): collect every global definition occurrence's
  /// group identity and source position into one `OverloadTable`. Light by design — it reads
  /// the store's per-file occurrence streams once, filters to definitions, and touches
  /// nothing else (no refiner, no demangler, no display names).
  private func buildOverloadTable(indexStoreDB: IndexStoreDB) -> OverloadTable {
    var definitions: [OverloadTable.Definition] = []
    for filePath in SwiftFileDiscovery.swiftFiles(underRepoPath: repoPath) {
      for occurrence in indexStoreDB.symbolOccurrences(inFilePath: filePath)
      where occurrence.roles.contains(.definition)
        && !occurrence.symbol.properties.contains(.local)
      {
        guard let parsed = USRSymbolParser.parse(occurrence.symbol.usr),
          let kind = USRSymbolMapper.declKind(for: occurrence.symbol),
          let name = USRSymbolMapper.sourceName(parsed: parsed, symbol: occurrence.symbol)
        else { continue }
        definitions.append(
          OverloadTable.Definition(
            usr: occurrence.symbol.usr,
            module: parsed.module,
            containerNames: parsed.containers.map(\.name),
            name: name,
            kind: kind,
            relativePath: relativePath(of: filePath),
            line: occurrence.location.line,
            utf8Column: occurrence.location.utf8Column
          ))
      }
    }
    return OverloadTable(definitions: definitions)
  }

  /// Source position of one definition occurrence — the ordering key for both the overload
  /// table (D-07) and the same-symbol merge decision (Pitfall 6).
  struct DefinitionPosition: Comparable {
    let relativePath: String
    let line: Int
    let utf8Column: Int

    static func < (lhs: DefinitionPosition, rhs: DefinitionPosition) -> Bool {
      if lhs.relativePath != rhs.relativePath { return lhs.relativePath < rhs.relativePath }
      if lhs.line != rhs.line { return lhs.line < rhs.line }
      return lhs.utf8Column < rhs.utf8Column
    }
  }

  /// A getter and a zero-arg method of the same name render the IDENTICAL canonical string
  /// (golden rows 9/14), so one `SymbolInformation` serves both; the surviving Kind is the
  /// definition that is LAST in source order, regardless of the order occurrences stream in
  /// (Pitfall 6, made explicit).
  static func winningSymbolInformation(
    _ candidates: [(info: Scip_SymbolInformation, position: DefinitionPosition)]
  ) -> Scip_SymbolInformation {
    precondition(!candidates.isEmpty)
    var winner = candidates[0]
    for candidate in candidates.dropFirst() where candidate.position > winner.position {
      winner = candidate
    }
    return winner.info
  }

  /// Requirement: SYM-03 / D-10 (02-02) — argv-normalized metadata. Raw `CommandLine.arguments`
  /// are deliberately NOT embedded in ToolInfo: CLI double-runs invoked with different
  /// `--output` paths must stay byte-identical, and argv also leaks local paths into shared
  /// artifacts. `projectRoot` stays — the same repo yields the same value. Internal (not
  /// private) as the determinism suite's test seam.
  func makeMetadata() -> Scip_Metadata {
    var toolInfo = Scip_ToolInfo()
    toolInfo.name = "scip-swift"
    toolInfo.version = converterVersion

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
    overloadTable: OverloadTable,
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
    var definedSymbols: [String: (info: Scip_SymbolInformation, position: DefinitionPosition)] = [:]
    let refiner = SwiftSyntaxRefiner(filePath: filePath)

    for occurrence in occurrences.sorted() {
      let symbol = occurrence.symbol
      let isLocal = symbol.properties.contains(.local)
      let overloadIndex = overloadTable.index(forUSR: symbol.usr)
      let symbolString =
        isLocal
        ? CanonicalSymbolFormatter.localSymbol(
          sourceName: symbol.name, ordinal: localNumberer.id(forUSR: symbol.usr))
        : canonicalSymbolString(
          for: symbol,
          isSystemLocation: occurrence.location.isSystem,
          locationModuleName: occurrence.location.moduleName,
          overloadIndex: overloadIndex
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
                locationModuleName: occurrence.location.moduleName,
                overloadIndex: overloadTable.index(forUSR: relSymbol.usr)
              )
            }
          )
        }
        // Same canonical string (getter + zero-arg method, or several local-context
        // re-manglings): the last definition in source order wins (Pitfall 6).
        let position = DefinitionPosition(
          relativePath: relativePath(of: filePath),
          line: occurrence.location.line,
          utf8Column: occurrence.location.utf8Column
        )
        if let existing = definedSymbols[symbolString] {
          if position > existing.position {
            definedSymbols[symbolString] = (symbolInformation, position)
          }
        } else {
          definedSymbols[symbolString] = (symbolInformation, position)
        }
      } else if !isLocal, referencedSymbols[symbolString] == nil, systemReferencedSymbols[symbolString] == nil {
        if occurrence.location.isSystem {
          systemReferencedSymbols[symbolString] = symbolInformation
        } else {
          referencedSymbols[symbolString] = symbolInformation
        }
      }
    }

    document.symbols = definedSymbols.values.map(\.info).sorted { $0.symbol < $1.symbol }
    // D-10 (02-02): the emitted occurrence order is the canonical one, never the store's.
    document.occurrences = Self.canonicalizedOccurrences(document.occurrences)
    return document
  }

  /// Requirement: SYM-03 / D-10 (02-02) — canonical occurrence post-pass, ported from the Go
  /// bindings' rules (`bindings/go/scip`: `sort.go` `SortOccurrences` over `occurrence_range.go`
  /// `Occurrence.Compare` / `Range.CompareStrict`): ascending by range start, then range end,
  /// then symbol string, with stable dedup on (symbol, range, roles) — the exact key
  /// `scip lint`'s `duplicateOccurrenceWarning` uses, so a getter/zero-arg-method pair sharing
  /// a name-token anchor cannot emit an exact duplicate. IndexStoreDB's store order (location,
  /// roles, symbol) is never the emitted order.
  static func canonicalizedOccurrences(_ occurrences: [Scip_Occurrence]) -> [Scip_Occurrence] {
    let sorted = occurrences.sorted { lhs, rhs in
      let (l, r) = (lhs.singleLineRange, rhs.singleLineRange)
      if l.line != r.line { return l.line < r.line }
      if l.startCharacter != r.startCharacter { return l.startCharacter < r.startCharacter }
      if l.endCharacter != r.endCharacter { return l.endCharacter < r.endCharacter }
      return lhs.symbol < rhs.symbol
    }

    var seen = Set<OccurrenceDedupKey>()
    seen.reserveCapacity(sorted.count)
    var deduped: [Scip_Occurrence] = []
    deduped.reserveCapacity(sorted.count)
    for occurrence in sorted where seen.insert(Self.occurrenceDedupKey(occurrence)).inserted {
      deduped.append(occurrence)
    }
    return deduped
  }

  /// Dedup key mirroring `scip lint`'s `occurrenceKey` (range + symbol roles), scoped per
  /// symbol string within one document.
  private struct OccurrenceDedupKey: Hashable {
    let symbol: String
    let line: Int32
    let startCharacter: Int32
    let endCharacter: Int32
    let symbolRoles: Int32
  }

  private static func occurrenceDedupKey(_ occurrence: Scip_Occurrence) -> OccurrenceDedupKey {
    OccurrenceDedupKey(
      symbol: occurrence.symbol,
      line: occurrence.singleLineRange.line,
      startCharacter: occurrence.singleLineRange.startCharacter,
      endCharacter: occurrence.singleLineRange.endCharacter,
      symbolRoles: occurrence.symbolRoles
    )
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
