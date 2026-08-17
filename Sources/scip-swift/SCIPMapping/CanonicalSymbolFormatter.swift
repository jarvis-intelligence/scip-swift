import IndexStoreDB

/// Requirement: SYM-03 — canonical symbol-string formatting for the frozen Phase-1 scip-swift
/// symbol scheme (ported from `swift/internal/symbol/namer.go` + `scheme.go` in the orchestrator
/// repo; the Phase-1 golden table is the byte-exact authority).
///
/// Every canonical global symbol has the header form
///
/// ```
/// scip-swift swiftpm <Module> . <descriptors>          (SwiftPM target modules)
/// scip-swift swift <Module> <swift-version> <descriptors>   (system/SDK modules)
/// ```
///
/// followed by descriptors chained without separators, one per ancestry node: namespace `M/`,
/// type `Shape#`, method `area().` (optionally with the `(+N)` disambiguator), term `origin.`,
/// type parameter `[T]`, parameter `(x)`, macro `Preview!`.
///
/// This type is the single place symbol strings are escaped and assembled (one escaping
/// implementation — `escapeSpaceField`/`escapeIdentifierName` live here; every other mapper
/// delegates). Document-scoped locals use the reserved `local <simple-identifier>` form.
///
/// Known limitations carried forward from the frozen scheme (scheme.go): disambiguators exist
/// only on Method descriptors, so Term-family retroactive collisions cannot carry `(+N)`; a
/// getter and a zero-arg method of the same name render the identical string (distinguished by
/// Kind only).
enum CanonicalSymbolFormatter {
  /// The SCIP symbol scheme prefix for all scip-swift global symbols.
  ///
  /// CAUTION: The scheme must not start with "local" — that prefix is reserved by the SCIP
  /// symbol grammar for document-scoped symbols.
  static let scheme = "scip-swift"

  /// The package manager for SwiftPM target modules.
  static let managerSwiftPM = "swiftpm"

  /// The package manager for system/SDK modules (the Swift standard library and SDK overlays).
  static let managerSystem = "swift"

  /// One node of a symbol's extended-type-aware ancestry, outermost first.
  struct Container {
    let name: String
    let kind: DeclKind
  }

  /// Everything needed to name a symbol; the Swift-side equivalent of the Go namer's
  /// `SymbolInput`. For a retroactive extension member `Module` is the module OWNING the
  /// extended type (SYM-02) and `ContainerPath` is the extended type's ancestry.
  struct SymbolInput {
    /// The owning Swift module (target) name.
    let module: String
    /// True for stdlib/SDK symbols (manager "swift").
    let isSystemModule: Bool
    /// The toolchain version reported for system modules; unused for SwiftPM targets. An empty
    /// version renders as the "." placeholder.
    let swiftToolchainVersion: String
    /// The extended-type-aware ancestry, outermost first. Empty means a top-level symbol.
    let containerPath: [Container]
    /// The source name; may be an operator or Unicode.
    let name: String
    /// The declaration category of `name`.
    let kind: DeclKind
    /// 0 for no disambiguator; N > 0 renders "(+N)", assigned in source declaration order.
    let overloadIndex: Int

    init(
      module: String,
      isSystemModule: Bool = false,
      swiftToolchainVersion: String = "",
      containerPath: [Container] = [],
      name: String,
      kind: DeclKind,
      overloadIndex: Int = 0
    ) {
      self.module = module
      self.isSystemModule = isSystemModule
      self.swiftToolchainVersion = swiftToolchainVersion
      self.containerPath = containerPath
      self.name = name
      self.kind = kind
      self.overloadIndex = overloadIndex
    }
  }

  /// Returns the canonical scip-swift SCIP symbol string for the input, or nil when the input
  /// is unnameable (empty module or empty name — no symbol is emitted for those, mirroring the
  /// Go namer's `ErrEmptyModule`/`ErrEmptyName`).
  static func symbol(_ input: SymbolInput) -> String? {
    guard !input.module.isEmpty, !input.name.isEmpty else { return nil }

    let manager = input.isSystemModule ? managerSystem : managerSwiftPM
    let version = input.isSystemModule ? input.swiftToolchainVersion : "."
    let header =
      "\(escapeSpaceField(scheme)) \(escapeSpaceField(manager)) "
      + "\(escapeSpaceField(input.module)) \(escapeSpaceField(version))"

    var descriptors: [String] = []
    descriptors.reserveCapacity(input.containerPath.count + 1)
    for container in input.containerPath {
      descriptors.append(descriptor(name: container.name, kind: container.kind, overloadIndex: 0))
    }
    descriptors.append(
      descriptor(name: input.name, kind: input.kind, overloadIndex: input.overloadIndex))

    return (descriptors.reduce(header + " ") { $0 + $1 })
  }

  /// Renders one descriptor: the escaped name plus the suffix the frozen scheme prescribes for
  /// the kind. Overload indices apply only to the Method family; an index greater than 0 on any
  /// other family is ignored rather than corrupted into the string.
  static func descriptor(name: String, kind: DeclKind, overloadIndex: Int) -> String {
    let escaped = escapeIdentifierName(name)
    switch kind {
    case .module:
      return "\(escaped)/"
    case .struct, .class, .enum, .protocol, .typeAlias:
      return "\(escaped)#"
    case .func, .method, .operator, .constructor, .destructor, .getter, .setter,
      .subscript, .protocolMethod:
      let disambiguator = overloadIndex > 0 ? "+\(overloadIndex)" : ""
      return "\(escaped)(\(disambiguator))."
    case .property, .constant, .variable, .enumCase:
      return "\(escaped)."
    case .typeParameter:
      return "[\(escaped)]"
    case .parameter:
      return "(\(escaped))"
    case .macro:
      return "\(escaped)!"
    }
  }

  /// A display name derived deterministically from a canonical symbol string itself
  /// ("<Module>.<container names>.<name>"), used for external symbols whose USR is not at
  /// hand (cache-served documents) — the string is the only self-describing input there is.
  /// Display-only: never a substitute for the canonical string.
  static func displayName(fromCanonicalString symbolString: String) -> String {
    var parts: [String] = []
    var chars = Array(symbolString)
    var index = 0

    func isSeparator(at position: Int) -> Bool {
      // A doubled space is a literal space inside a field; a single space separates fields.
      guard position < chars.count, chars[position] == " " else { return false }
      if position + 1 < chars.count, chars[position + 1] == " " {
        return false
      }
      return true
    }

    // Header: scheme, manager, module, version — the module (field 3) prefixes the name.
    var field = 0
    var module = ""
    while index < chars.count, field < 4 {
      if isSeparator(at: index) {
        field += 1
        index += 1
        continue
      }
      if chars[index] == " " {
        // Literal (doubled) space — collapse to one.
        if field == 2 { module.append(" ") }
        index += 2
        continue
      }
      if field == 2 { module.append(chars[index]) }
      index += 1
    }
    parts.append(module)

    // Descriptor chain: decode names and skip suffixes.
    while index < chars.count {
      let c = chars[index]
      if c == "(" {
        // Parameter descriptor: name inside parentheses.
        index += 1
        let name = readDescriptorName(&chars, &index, terminators: [")"])
        index = min(index + 1, chars.count)
        parts.append(name)
      } else if c == "[" {
        // Type-parameter descriptor: name inside brackets.
        index += 1
        let name = readDescriptorName(&chars, &index, terminators: ["]"])
        index = min(index + 1, chars.count)
        parts.append(name)
      } else {
        let name = readDescriptorName(&chars, &index, terminators: ["#", "/", ".", "!", "("])
        if !name.isEmpty { parts.append(name) }
        // Skip the suffix: a single char, or a Method "()"/"(+N)." region.
        if index < chars.count, chars[index] == "(" {
          while index < chars.count, chars[index] != ")" { index += 1 }
          index = min(index + 1, chars.count)
          if index < chars.count, chars[index] == "." { index += 1 }
        } else if index < chars.count {
          index += 1
        }
      }
    }
    return parts.filter { !$0.isEmpty }.joined(separator: ".")
  }

  private static func readDescriptorName(
    _ chars: inout [Character], _ index: inout Int, terminators: [Character]
  ) -> String {
    var name = ""
    while index < chars.count {
      let c = chars[index]
      if terminators.contains(c) { break }
      if c == "`" {
        // Backtick-escaped name: literal backticks are doubled inside.
        index += 1
        while index < chars.count {
          if chars[index] == "`" {
            if index + 1 < chars.count, chars[index + 1] == "`" {
              name.append("`")
              index += 2
            } else {
              index += 1
              break
            }
          } else {
            name.append(chars[index])
            index += 1
          }
        }
        continue
      }
      name.append(c)
      index += 1
    }
    return name
  }

  /// Returns a document-scoped local symbol string `local <id>` where the id is the source
  /// name sanitized to a simple identifier — every rune outside the simple-identifier set
  /// collapses to `_` — with the ordinal appended as `_N` when it is greater than zero
  /// (frozen Phase-1 rule; `LocalSymbolNumberer` stays the ordinal source). Unicode source
  /// names (emoji, CJK) never appear raw in a local id.
  static func localSymbol(sourceName: String, ordinal: Int) -> String {
    var id = String(
      sourceName.map { isIdentifierCharacter($0) ? $0 : "_" })
    if id.isEmpty {
      id = "_"
    }
    if ordinal > 0 {
      id += "_\(ordinal)"
    }
    return "local \(id)"
  }

  // MARK: - Escaping (the single implementation; SCIPSymbolFormatter delegates here)

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

  static func isIdentifierCharacter(_ character: Character) -> Bool {
    if character == "_" || character == "+" || character == "-" || character == "$" {
      return true
    }
    return character.isASCII && (character.isLetter || character.isNumber)
  }
}
