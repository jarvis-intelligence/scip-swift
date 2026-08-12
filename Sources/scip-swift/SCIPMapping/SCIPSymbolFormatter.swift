import IndexStoreDB

/// Requirement: IndexStoreDB to SCIP protobuf conversion (task 3.1).
///
/// Renders an IndexStoreDB `Symbol` into the canonical SCIP symbol string, per the grammar
/// documented on the `Symbol` message in `scip.proto`:
///
/// ```
/// <symbol> ::= <scheme> ' ' <package> ' ' (<descriptor>)+ | 'local ' <local-id>
/// <package> ::= <manager> ' ' <package-name> ' ' <version>
/// ```
///
/// Swift's USR (Unified Symbol Resolution) string is already a compiler-guaranteed,
/// project-wide-unique stable identifier, so this uses the raw USR verbatim as a single `Term`
/// descriptor rather than attempting to demangle it into a namespace/type/method descriptor
/// chain — see design.md Decision 3 / Open Questions for the full rationale.
///
/// Symbols IndexStoreDB marks `.local` (locals, parameters, etc. that cannot be referenced
/// outside their document) are instead rendered as SCIP local symbols (`local <n>`), numbered
/// per-document by `LocalSymbolNumberer`.
enum SCIPSymbolFormatter {
  static let scheme = "scip-swift"

  static func globalSymbolString(packageManager: String, moduleName: String, version: String = "", usr: String) -> String {
    let manager = escapeSpaceField(packageManager)
    let packageName = escapeSpaceField(moduleName)
    let versionField = escapeSpaceField(version)
    let descriptor = "\(escapeIdentifierName(usr))."
    return "\(escapeSpaceField(scheme)) \(manager) \(packageName) \(versionField) \(descriptor)"
  }

  static func localSymbolString(localID: Int) -> String {
    "local \(localID)"
  }

  /// Escapes a `<scheme>`/`<manager>`/`<package-name>`/`<version>` field: spaces are doubled, and
  /// an empty value is represented with the grammar's `.` placeholder.
  static func escapeSpaceField(_ raw: String) -> String {
    guard !raw.isEmpty else { return "." }
    return raw.replacingOccurrences(of: " ", with: "  ")
  }

  /// Escapes a descriptor `<name>` per the `<identifier>` production: strings made up entirely of
  /// `<identifier-character>` (`_ + - $` or ASCII letters/digits) are used as-is; anything else is
  /// wrapped in backticks with literal backticks doubled.
  static func escapeIdentifierName(_ raw: String) -> String {
    guard !raw.isEmpty, raw.allSatisfy(isIdentifierCharacter) else {
      return "`\(raw.replacingOccurrences(of: "`", with: "``"))`"
    }
    return raw
  }

  private static func isIdentifierCharacter(_ character: Character) -> Bool {
    if character == "_" || character == "+" || character == "-" || character == "$" {
      return true
    }
    return character.isASCII && (character.isLetter || character.isNumber)
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
