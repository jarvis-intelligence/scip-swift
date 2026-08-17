import IndexStoreDB

/// Requirement: SYM-03 / D-06 — the raw-USR fallback renderer.
///
/// Since the Phase-2 symbol-scheme port, canonical symbols are descriptor chains assembled by
/// `CanonicalSymbolFormatter` from the parsed USR. When `USRSymbolParser` cannot handle a USR,
/// this type emits the pre-Phase-2 form — the raw USR verbatim as a single backtick-escaped
/// `Term` descriptor — under the canonical module header (`scip-swift swiftpm <Module> .` for
/// target modules, `scip-swift swift <Module> <toolchain>` for system modules). Indexing never
/// fails or drops a symbol because of an exotic USR; the caller records each fallback in
/// `SymbolMappingDiagnostics`.
///
/// The escaping helpers remain re-exported here (delegating to `CanonicalSymbolFormatter`, the
/// single implementation) so existing callers compile unchanged.
enum SCIPSymbolFormatter {
  static let scheme = CanonicalSymbolFormatter.scheme

  /// The D-06 fallback form: raw USR as an opaque Term under the canonical module header.
  static func fallbackSymbolString(
    isSystem: Bool,
    moduleName: String,
    toolchainVersion: String,
    usr: String
  ) -> String {
    globalSymbolString(
      packageManager: isSystem
        ? CanonicalSymbolFormatter.managerSystem : CanonicalSymbolFormatter.managerSwiftPM,
      moduleName: moduleName,
      version: isSystem ? toolchainVersion : "",
      usr: usr
    )
  }

  static func globalSymbolString(packageManager: String, moduleName: String, version: String = "", usr: String) -> String {
    let manager = escapeSpaceField(packageManager)
    let packageName = escapeSpaceField(moduleName)
    let versionField = escapeSpaceField(version)
    let descriptor = "\(escapeIdentifierName(usr))."
    return "\(escapeSpaceField(scheme)) \(manager) \(packageName) \(versionField) \(descriptor)"
  }

  /// Escapes a `<scheme>`/`<manager>`/`<package-name>`/`<version>` field. Delegates to
  /// `CanonicalSymbolFormatter` — exactly one escaping implementation exists.
  static func escapeSpaceField(_ raw: String) -> String {
    CanonicalSymbolFormatter.escapeSpaceField(raw)
  }

  /// Escapes a descriptor `<name>` per the `<identifier>` production. Delegates to
  /// `CanonicalSymbolFormatter` — exactly one escaping implementation exists.
  static func escapeIdentifierName(_ raw: String) -> String {
    CanonicalSymbolFormatter.escapeIdentifierName(raw)
  }
}

/// Assigns stable, per-document-scoped SCIP local-symbol IDs to IndexStoreDB USRs marked
/// `.local`. SCIP local symbols are only meaningful within a single `Document`, so a fresh
/// numberer must be used per document.
struct LocalSymbolNumberer {
  private var idsByUSR: [String: Int] = [:]
  private var nextID = 0

  mutating func id(forUSR usr: String) -> Int {
    if let existing = idsByUSR[usr] {
      return existing
    }
    let id = nextID
    nextID += 1
    idsByUSR[usr] = id
    return id
  }
}
