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
  /// SYM-04/NAV-03 (03-03): the indexed repo's Package.swift target map — nil when no
  /// readable manifest exists. Serves the import-symbol manager decision (D-17) and
  /// test-target document detection (D-18).
  let packageTargets: PackageTargetMap?

  /// Per-run D-06 fallback accounting, surfaced as a diagnostic at the end of `build()`.
  let symbolMappingDiagnostics = SymbolMappingDiagnostics()

  /// REL-01 / D-21 (04-02) — per-run accounting of relationship-emission diagnostics:
  /// the ObjC-superclass SwiftSyntax fallback edge count, surfaced at build end next
  /// to the D-06 fallback summary. A class (not a value) so the non-mutating document
  /// pass can record through it, mirroring `SymbolMappingDiagnostics`.
  let relationshipDiagnostics = RelationshipDiagnostics()

  /// Requirement: REL-01 / D-21 (04-02) — the bounded ObjC fallback's counter. Count
  /// only, no paths (ASVS V8 diagnostics discipline).
  final class RelationshipDiagnostics {
    private(set) var objcSuperclassFallbackEdgeCount = 0

    func recordObjCSuperclassFallbackEdge() {
      objcSuperclassFallbackEdgeCount += 1
    }

    var summary: String? {
      guard objcSuperclassFallbackEdgeCount > 0 else { return nil }
      return
        "\(objcSuperclassFallbackEdgeCount) superclass edge(s) emitted via the ObjC SwiftSyntax fallback (D-21, bounded: class clauses whose store record carries no baseOf)"
    }
  }

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
    self.packageTargets = PackageTargetMap(packageDirectory: repoPath)
  }

  func build() throws -> Scip_Index {
    let indexStoreDB = try IndexStoreLoader.open(storePath: indexStorePath, databasePath: databasePath)
    indexStoreDB.pollForUnitChangesAndWait()

    let demangler = demangle ? USRDemangler.load() : nil

    // Phase A (D-07): a light definitions pre-pass fills the USR-keyed overload table before
    // any document is emitted, so definitions and references render identical strings by
    // construction (Pitfall 4 — the lint missingSymbolForOccurrenceError contract).
    let overloadTable = buildOverloadTable(indexStoreDB: indexStoreDB)

    // D-10 / T-02-04 (02-02 Task 3): the overload-table fingerprint is a GLOBAL cache
    // validation key. Documents are keyed by their own file's composite (relativePath,
    // content hash) key, but overload
    // indices depend on every group member repo-wide — an overload added in file B shifts the
    // (+N) suffixes of unchanged file A's symbols. Any fingerprint change — or a cache with no
    // (trustable) manifest — wholesale-invalidates docs/ via the existing invalidateAll()
    // path. `isCompatibleWith` deliberately does not carry this key: it depends on the opened
    // store, which the caller cannot know before the build.
    if let cacheStore {
      let fingerprint = overloadTable.cacheValidationFingerprint()
      if let manifest = cacheStore.loadManifest() {
        if manifest.overloadTableFingerprint != fingerprint {
          try? cacheStore.invalidateAll()
          var updated = manifest
          updated.overloadTableFingerprint = fingerprint
          try? cacheStore.saveManifest(updated)
        }
      } else {
        // No manifest: docs/ content cannot be trusted (older engine, or direct-builder use
        // that never went through IndexCommand's manifest block). Discard it and record the
        // fingerprint; the static version keys are IndexCommand's to fill — "" never matches
        // its check, so a later CLI run invalidates once more and writes the authoritative
        // manifest.
        try? cacheStore.invalidateAll()
        try? cacheStore.saveManifest(IndexManifest(
          toolchainVersion: ToolchainInfo.pinnedSwiftVersion,
          converterVersion: converterVersion,
          indexstoreDbRevision: "",
          buildToolName: buildToolName,
          overloadTableFingerprint: fingerprint
        ))
      }
    }

    var index = Scip_Index()
    index.metadata = makeMetadata()

    var referencedSymbols: [String: Scip_SymbolInformation] = [:]
    var systemReferencedSymbols: [String: Scip_SymbolInformation] = [:]
    var definedSymbolStrings: Set<String> = []
    // D-09 (02-02): per-document canonicalSymbol -> USR side maps, keyed by relativePath. Fresh
    // documents capture theirs during emission; cache-served documents load theirs from
    // docs/<composite-key>.usrmap — either way the external display-name pass never
    // reverse-extracts a USR from the symbol string.
    var usrMapsByPath: [String: [String: String]] = [:]

    for filePath in SwiftFileDiscovery.swiftFiles(underRepoPath: repoPath) {
      var document: Scip_Document?
      let path = relativePath(of: filePath)

      if let cacheStore {
        let contentHash = try? ContentHasher.sha256Hex(of: filePath)
        if let hash = contentHash {
          if let cached = cacheStore.loadDocument(relativePath: path, hash: hash),
             cached.relativePath == path,  // fail-safe: key drift serves a miss, never a wrong document
             indexStoreDB.dateOfLatestUnitFor(filePath: filePath) != nil {
            document = cached
            usrMapsByPath[path] = cacheStore.loadUSRMap(relativePath: path, hash: hash) ?? [:]
          }
        }

        if document == nil {
          if let (fresh, sideMap) = makeDocument(
            filePath: filePath,
            indexStoreDB: indexStoreDB,
            demangler: demangler,
            overloadTable: overloadTable,
            referencedSymbols: &referencedSymbols,
            systemReferencedSymbols: &systemReferencedSymbols
          ) {
            if let hash = contentHash {
              try? cacheStore.saveDocument(fresh, relativePath: path, hash: hash)
              // The side map rides the same composite key and document directory as its
              // .scipdoc — it invalidates atomically with the document (T-02-05).
              try? cacheStore.saveUSRMap(sideMap, relativePath: path, hash: hash)
            }
            usrMapsByPath[fresh.relativePath] = sideMap
            document = fresh
          }
        }
      } else {
        if let (fresh, sideMap) = makeDocument(
          filePath: filePath,
          indexStoreDB: indexStoreDB,
          demangler: demangler,
          overloadTable: overloadTable,
          referencedSymbols: &referencedSymbols,
          systemReferencedSymbols: &systemReferencedSymbols
        ) {
          usrMapsByPath[fresh.relativePath] = sideMap
          document = fresh
        }
      }

      if let document {
        definedSymbolStrings.formUnion(document.symbols.map(\.symbol))
        index.documents.append(document)
      }
    }

    // D-10 (02-02): documents ascend by relativePath, mirroring Go `SortDocuments`. Discovery
    // already walks in sorted order; sorting here makes the emitted contract explicit rather
    // than incidental on the directory walk.
    var externalSymbols: [String: Scip_SymbolInformation] = [:]
    for doc in index.documents {
      let usrSideMap = usrMapsByPath[doc.relativePath] ?? [:]
      // REL-01 (04-02): the mint scan covers OCCURRENCES and RELATIONSHIP TARGETS —
      // a relationship target that never appears as an occurrence symbol (e.g. the
      // CustomStringConvertible.description requirement) must still mint into
      // external_symbols, because `scip lint` requires every relationship target to
      // exist as an external symbol or some document's symbol
      // (cmd/scip/lint.go:186-192 — the live 04-01 finding). The walk reads
      // document.symbols bytes, so fresh and cache-served documents mint identically.
      var mintCandidates = doc.occurrences.map(\.symbol)
      mintCandidates.append(
        contentsOf: doc.symbols.flatMap { $0.relationships.map(\.symbol) })
      for sym in mintCandidates {
        if !sym.hasPrefix("local ") && !definedSymbolStrings.contains(sym) && externalSymbols[sym] == nil {
          var info = Scip_SymbolInformation()
          info.symbol = sym
          // D-06 fallback symbols ride the canonicalSymbol -> USR side map (captured during
          // emission on fresh runs, loaded from docs/<composite-key>.usrmap on cache-hit
          // runs), so they keep their demangled display names identically in both. Canonical
          // descriptor chains never enter the side map: their display name derives
          // deterministically from the symbol string itself.
          if let usr = usrSideMap[sym], let demangler {
            info.displayName = demangler.demangledDisplayName(usr: usr) ?? ""
          } else if let moduleName = CanonicalSymbolFormatter.moduleDisplayName(fromCanonicalString: sym) {
            // SYM-04 (D-17, 03-03): module symbols land in external_symbols with the
            // module's own name — derived from the canonical string itself so fresh and
            // cache-hit runs produce identical bytes. NOT gated on the demangler (WR-02,
            // 03 review): the derivation is pure string work, so --no-demangle runs name
            // module symbols too. Module USRs always parse, so canonical module strings
            // never enter the fallback side map above — the branch order is total.
            info.displayName = moduleName
          } else if let demangler {
            info.displayName = CanonicalSymbolFormatter.displayName(fromCanonicalString: sym)
          }
          externalSymbols[sym] = info
        }
      }
    }
    index.externalSymbols = externalSymbols.values.sorted { $0.symbol < $1.symbol }

    if let fallbackSummary = symbolMappingDiagnostics.summary {
      print("warning: \(fallbackSummary)")
    }
    if let relationshipSummary = relationshipDiagnostics.summary {
      print("warning: \(relationshipSummary)")
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
    overloadIndex: Int = 0,
    fallbackRecorder: USRSideMapRecorder? = nil
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
    let fallback = SCIPSymbolFormatter.fallbackSymbolString(
      isSystem: isSystemLocation,
      moduleName: locationModuleName,
      toolchainVersion: ToolchainInfo.pinnedSwiftVersion,
      usr: symbol.usr
    )
    fallbackRecorder?.record(symbolString: fallback, usr: symbol.usr)
    return fallback
  }

  /// Requirement: SYM-03 / D-09 (02-02, research Pitfall 3) — accumulates the per-document
  /// canonicalSymbol -> USR side map for D-06 fallback symbols during emission; persisted by
  /// `CacheStore.saveUSRMap` so cache-hit runs demangle external display names identically to
  /// fresh runs. A class (not a value) so the relationship-formatter closure can record through
  /// it without capturing inout storage.
  final class USRSideMapRecorder {
    private(set) var entries: [String: String] = [:]

    func record(symbolString: String, usr: String) {
      entries[symbolString] = usr
    }
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
  ///
  /// D-14 (02-03): the pinned scip CLI version rides as ONE constant synthetic entry — a
  /// fixed string, never argv — so the pin is visible in ToolInfo output while the
  /// argv-insensitivity guarantee holds byte-for-byte.
  func makeMetadata() -> Scip_Metadata {
    var toolInfo = Scip_ToolInfo()
    toolInfo.name = "scip-swift"
    toolInfo.version = converterVersion
    toolInfo.arguments = ["scip-cli-version=\(ScipSwiftVersion.scipCliVersion)"]

    var metadata = Scip_Metadata()
    metadata.toolInfo = toolInfo
    metadata.projectRoot = URL(fileURLWithPath: repoPath, isDirectory: true).absoluteString
    metadata.textDocumentEncoding = .utf8
    return metadata
  }

  /// Returns nil when the store holds no occurrences for the file; otherwise the document plus
  /// its canonicalSymbol -> USR side map for D-06 fallback symbols (D-09, 02-02).
  private func makeDocument(
    filePath: String,
    indexStoreDB: IndexStoreDB,
    demangler: USRDemangler?,
    overloadTable: OverloadTable,
    referencedSymbols: inout [String: Scip_SymbolInformation],
    systemReferencedSymbols: inout [String: Scip_SymbolInformation]
  ) -> (document: Scip_Document, usrSideMap: [String: String])? {
    let occurrences = indexStoreDB.symbolOccurrences(inFilePath: filePath)
    guard !occurrences.isEmpty else { return nil }

    var document = Scip_Document()
    document.language = "Swift"
    document.relativePath = relativePath(of: filePath)
    document.positionEncoding = .utf8CodeUnitOffsetFromLineStart

    var localNumberer = LocalSymbolNumberer()
    var definedSymbols: [String: (info: Scip_SymbolInformation, position: DefinitionPosition)] = [:]
    let refiner = SwiftSyntaxRefiner(filePath: filePath)
    let fallbackRecorder = USRSideMapRecorder()
    // NAV-03 (D-18, 03-03): test-target documents — PRIMARY: relativePath under a
    // Package.swift `.testTarget`'s path; SECONDARY: the document's store moduleName
    // (uniform per document, empirically) names a test target. Computed once per
    // document; every occurrence in it — imports included — ORs in the Test bit below.
    // The store's SymbolProperty.unitTest path stays as a belt in SymbolRoleMapping.
    let isTestTargetDocument = packageTargets?.isTestTargetDocument(
      relativePath: document.relativePath,
      moduleName: occurrences.first?.location.moduleName) ?? false

    // REL-01 / D-21 / D-23 (04-02) — the clause-relation harvest state. Clause
    // REFERENCE occurrences carry the store's pairing relations (base ref → derived
    // entity; 04-RESEARCH Q1): they are collected per document below and become
    // type-level is_implementation edges attached after the occurrence loop.
    // extensionTypeByUSR maps each s:e: extension USR to the extended TYPE it pairs
    // (the same-position extendedBy pairing — the type ref on the clause line always
    // precedes the protocol refs in canonical occurrence order).
    var extensionTypeByUSR: [String: (canonical: String, kind: Scip_SymbolInformation.Kind)] = [:]
    var clauseEdges: [(subject: String, kind: Scip_SymbolInformation.Kind?, relationship: Scip_Relationship)] = []
    var classDefinitions: [(canonical: String, name: String, moduleName: String)] = []

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
          isSystemLocation: Self.effectiveIsSystemLocation(
            for: symbol, storeReported: occurrence.location.isSystem, packageTargets: packageTargets),
          locationModuleName: occurrence.location.moduleName,
          overloadIndex: overloadIndex,
          fallbackRecorder: fallbackRecorder
        )

      var scipOccurrence = Scip_Occurrence()
      scipOccurrence.symbol = symbolString
      scipOccurrence.symbolRoles = SymbolRoleMapping.scipRoles(for: occurrence.roles, symbol: symbol)
      if Self.isWrittenImport(symbol: symbol, roles: occurrence.roles) {
        // SYM-04 (D-17, 03-03): REPLACE, never OR — the (symbol, range, roles) dedup key
        // would otherwise keep both the old reference line and the Import occurrence at
        // the same anchor. Implicit module occurrences (Swift Testing macro expansion)
        // never take the Import role.
        scipOccurrence.symbolRoles = Int32(Scip_SymbolRole.import.rawValue)
      }
      if Self.isGeneratedPath(filePath) {
        scipOccurrence.symbolRoles |= Int32(Scip_SymbolRole.generated.rawValue)
      }
      if isTestTargetDocument {
        scipOccurrence.symbolRoles |= Int32(Scip_SymbolRole.test.rawValue)
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
          locationModuleName: occurrence.location.moduleName,
          fallbackRecorder: fallbackRecorder
        )
      }

      // REL-01 / D-21 / D-23 (04-02) — the clause-relation harvest. Unlike the
      // definition-gated witness emission below, type-level edges derive from clause
      // REFERENCE occurrences: `.baseOf`/`.extendedBy` relations never ride member
      // definitions, and implicit occurrences (synthesized conformances, default-
      // implementation sites) are filtered out — an undeclared "conformance" can
      // never become an edge (availability is not declaration, plan prohibition).
      if !isLocal && !occurrence.roles.contains(.implicit) {
        if occurrence.roles.contains(.definition), symbol.kind == .class {
          classDefinitions.append((symbolString, symbol.name, occurrence.location.moduleName))
        }
        for relation in occurrence.relations {
          if relation.roles.contains(.extendedBy), occurrence.symbol.kind != .extension {
            // The TYPE reference of `extension X: P` — the same-position pairing
            // anchor keyed by the extension USR the baseOf relations name.
            extensionTypeByUSR[relation.symbol.usr] = (symbolString, symbolInformation.kind)
          }
          guard relation.roles.contains(.baseOf) else { continue }
          // The edge TARGET is this occurrence's own canonical string (the base);
          // the SUBJECT is the relation's symbol — the derived TYPE for in-decl
          // clauses, or the extension's TYPE via the same-position pairing for
          // extension-declared conformances (never the s:e: extension symbol itself,
          // pitfall 3). A pairing miss skips the edge — positional guessing is
          // prohibited.
          let subject: String
          var carrierKind: Scip_SymbolInformation.Kind? = nil
          if relation.symbol.kind == .extension {
            guard let extended = extensionTypeByUSR[relation.symbol.usr] else { continue }
            subject = extended.canonical
            carrierKind = extended.kind
          } else {
            subject = canonicalSymbolString(
              for: relation.symbol,
              isSystemLocation: occurrence.location.isSystem,
              locationModuleName: occurrence.location.moduleName,
              fallbackRecorder: fallbackRecorder)
          }
          let target = symbolString
          for relationship in RelationshipMapping.scipRelationships(
            for: [relation], symbolFormatter: { _ in target })
          {
            clauseEdges.append((subject, carrierKind, relationship))
          }
        }
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
                overloadIndex: overloadTable.index(forUSR: relSymbol.usr),
                fallbackRecorder: fallbackRecorder
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
    // REL-01 / D-23 (04-02): attach the harvested type-level edges. Subjects defined
    // in THIS document merge into their SymbolInformation; subjects defined elsewhere
    // (retroactive extension-declared conformances — `extension X: P` in a different
    // file/module than X) get a CARRIER SymbolInformation for the type's canonical
    // string in this document: D-23 pins the edge where DECLARED, and the clause's
    // extendedBy ref already anchors the type here. Lint-legal (duplicateSymbolInfo
    // warnings are same-document only, cmd/scip/lint.go:143-148); display name and
    // kind derive from the canonical string / pairing ref, so fresh and cache-hit runs
    // emit identical bytes.
    var carrierSymbols: [String: Scip_SymbolInformation] = [:]
    func attachTypeLevelEdge(_ relationship: Scip_Relationship, to subject: String, kind: Scip_SymbolInformation.Kind?) {
      if var existing = definedSymbols[subject] {
        existing.info.relationships.append(relationship)
        definedSymbols[subject] = existing
      } else if var carrier = carrierSymbols[subject] {
        carrier.relationships.append(relationship)
        carrierSymbols[subject] = carrier
      } else {
        var carrier = Scip_SymbolInformation()
        carrier.symbol = subject
        carrier.displayName = CanonicalSymbolFormatter.displayName(fromCanonicalString: subject)
        if let kind {
          carrier.kind = kind
        }
        carrier.relationships = [relationship]
        carrierSymbols[subject] = carrier
      }
    }
    for edge in clauseEdges {
      attachTypeLevelEdge(edge.relationship, to: edge.subject, kind: edge.kind)
    }

    // D-21 (04-02) — the bounded ObjC fallback (ObjCSuperclassClauseMap, D-06-style
    // documented + counted): class definitions that received NO type-level edge at
    // all — the proven store gap for ObjC-rooted superclasses (`class X: NSObject`
    // records no baseOf) — get their superclass edge from the clause syntax. The
    // target renders through the same D-06 fallback path the store's own NSObject
    // member USRs take (`c:objc(cs)<Name>` Term under the class's module), and every
    // fallback edge is counted in diagnostics. Classes whose superclass recorded
    // normally (all Swift-rooted clauses) already carry their edge and never reach
    // here.
    if let clauseMap = ObjCSuperclassClauseMap(filePath: filePath) {
      let edgeSubjects = Set(clauseEdges.map(\.subject))
      for classDefinition in classDefinitions
      where !edgeSubjects.contains(classDefinition.canonical) {
        guard let superclass = clauseMap.superclass(ofClassName: classDefinition.name)
        else { continue }
        let targetSymbol = Symbol(
          usr: "c:objc(cs)\(superclass)", name: superclass, kind: .class, subKind: .none,
          language: .swift)
        let target = canonicalSymbolString(
          for: targetSymbol,
          isSystemLocation: false,
          locationModuleName: classDefinition.moduleName,
          fallbackRecorder: fallbackRecorder)
        // The flag assignment rides the real clause-mapping path (baseOf →
        // isImplementation only): the synthesized relation formats to the fallback
        // target string.
        let fallbackRelation = SymbolRelation(symbol: targetSymbol, roles: .baseOf)
        guard let relationship = RelationshipMapping.scipRelationships(
          for: [fallbackRelation], symbolFormatter: { _ in target }).first
        else { continue }
        attachTypeLevelEdge(relationship, to: classDefinition.canonical, kind: nil)
        relationshipDiagnostics.recordObjCSuperclassFallbackEdge()
      }
    }

    document.symbols = (definedSymbols.values.map(\.info) + carrierSymbols.values)
      .map { info -> Scip_SymbolInformation in
        var canonical = info
        canonical.relationships = Self.canonicalizedRelationships(info.relationships)
        return canonical
      }
      .sorted { $0.symbol < $1.symbol }
    // D-10 (02-02): the emitted occurrence order is the canonical one, never the store's.
    document.occurrences = Self.canonicalizedOccurrences(document.occurrences)
    return (document, fallbackRecorder.entries)
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

  /// Requirement: REL-01 / D-10 (04-02) — canonical relationship post-pass, ported from
  /// the Go bindings (`bindings/go/scip`: `canonicalize.go:90-93` `CanonicalizeRelationships
  /// = SortRelationships(FlattenRelationship(…))`; `flatten.go:88-108` OR-merges the four
  /// flags per target symbol; `sort.go:121-128` sorts ascending by relationship symbol
  /// string). Emitted relationships are pre-canonicalized so the byte-identity double-run
  /// gate holds without post-processing and `scip lint`'s multipleRelationshipWarning
  /// never fires on a merged pair.
  static func canonicalizedRelationships(_ relationships: [Scip_Relationship]) -> [Scip_Relationship] {
    var mergedBySymbol: [String: Scip_Relationship] = [:]
    mergedBySymbol.reserveCapacity(relationships.count)
    for relationship in relationships {
      if var combined = mergedBySymbol[relationship.symbol] {
        combined.isReference = combined.isReference || relationship.isReference
        combined.isImplementation = combined.isImplementation || relationship.isImplementation
        combined.isTypeDefinition = combined.isTypeDefinition || relationship.isTypeDefinition
        combined.isDefinition = combined.isDefinition || relationship.isDefinition
        mergedBySymbol[relationship.symbol] = combined
      } else {
        mergedBySymbol[relationship.symbol] = relationship
      }
    }
    return mergedBySymbol.values.sorted { $0.symbol < $1.symbol }
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

  /// SYM-04 (D-17, 03-03): a written `import` / `@testable import` statement — the store
  /// surfaces it as a non-implicit module occurrence anchored on the module-name token
  /// (past any `@testable` attribute). Implicit module occurrences (Swift Testing macro
  /// expansion at #expect/@Suite sites) are excluded so the index never floods with
  /// Import roles at unrelated positions.
  static func isWrittenImport(symbol: Symbol, roles: SymbolRole) -> Bool {
    symbol.usr.hasPrefix("c:@M@") && symbol.kind == .module && !roles.contains(.implicit)
  }

  /// SYM-04 (D-17, 03-03): for module symbols the header manager comes from the
  /// Package.swift target map — a module named in the target list is repo-local
  /// (`swiftpm` header); everything else is external (`swift` + pinned version). The
  /// store reports isSystem=false at user-file import sites, so the map is the only
  /// source of this classification. A nil map (no manifest) conservatively classifies
  /// every module as external.
  static func effectiveIsSystemLocation(
    for symbol: Symbol, storeReported: Bool, packageTargets: PackageTargetMap?
  ) -> Bool {
    guard symbol.kind == .module, symbol.usr.hasPrefix("c:@M@") else { return storeReported }
    let moduleName = String(symbol.usr.dropFirst("c:@M@".count))
    return !(packageTargets?.containsTarget(named: moduleName) ?? false)
  }
}
