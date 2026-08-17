/// Requirement: SYM-03 / D-05 — total Swift USR grammar parser (USR string -> ParsedUSR).
///
/// Parses the common shapes of compiler-emitted USRs directly (never via the demangler —
/// D-05 keeps `libswiftDemangle` display-only): the `s:` scheme prefix, the leading
/// module (length-prefixed) or stdlib substitution, the identifier+kind-letter container
/// chain (V struct, C class, O enum, P protocol, a typealias, F/f func), retroactive
/// extension `E` contexts (extended type + extending module marker), and the final entity
/// name. The trailing signature region is treated as opaque — skipped, never interpreted.
///
/// Security posture (T-02-01): the parser is TOTAL over adversarial input. Every claimed
/// length is checked against the remaining input, there are no force-unwraps and no
/// unbounded recursion or loops. Any parse miss returns nil and the caller falls back to
/// the D-06 raw-USR Term form — indexing never fails or drops a symbol because of an
/// exotic USR.
enum USRSymbolParser {
  /// The parsed identity of one `s:` USR, ready for canonical symbol assembly.
  struct ParsedUSR {
    /// The owning Swift module. For a retroactive extension member this is the module OWNING
    /// the extended type (SYM-02) — derived from the USR's leading context, never from the
    /// declaring file's module.
    let module: String
    /// True when the module was resolved from a stdlib substitution (the Swift module and its
    /// standard types) — such symbols use the system-module header.
    let isSystemModule: Bool
    /// The extended-type-aware ancestry of the entity, outermost first. A retroactive
    /// extension member carries the extended type here; an extension declared on the types of
    /// another module records that module via `extendingModule` instead.
    let containers: [CanonicalSymbolFormatter.Container]
    /// The entity's own source name (the word at its declaration position in the USR).
    let name: String
    /// The module that declares a retroative extension member, when the USR carries an `E`
    /// extension marker. Informational only — the canonical header always uses `module`
    /// (the extended type's owner), never this value.
    let extendingModule: String?
  }

  /// Parses a USR. Returns nil on any miss — unparseable shapes, non-`s:` schemes, punycode
  /// (`00`-prefixed) identifiers, local/argument `A...` contexts, and truncated or adversarial
  /// input all take the D-06 fallback path.
  static func parse(_ usr: String) -> ParsedUSR? {
    var cursor = Cursor(usr)
    guard cursor.consume(prefix: "s:") else { return nil }

    var module: String
    var isSystem = false
    var containers: [CanonicalSymbolFormatter.Container] = []

    // Head context: either a stdlib substitution (system module) or the owning module word.
    if let substitution = cursor.peekSubstitution() {
      guard let resolved = stdlibSubstitution(substitution) else { return nil }
      cursor.consumeSubstitution()
      module = "Swift"
      isSystem = true
      containers.append(resolved.container)
      // A bare `s:SS` names the substituted type itself; a following word demotes it to a
      // container of the upcoming entity. Anything that remains but fails to parse is a
      // miss — never fall through to the bare-substitution shape on non-empty input.
      if cursor.isAtEnd {
        return ParsedUSR(
          module: module,
          isSystemModule: isSystem,
          containers: [],
          name: resolved.container.name,
          extendingModule: nil
        )
      }
      guard let entity = parseEntity(afterHead: &cursor, containers: &containers) else {
        return nil
      }
      return finish(module: module, isSystem: isSystem, containers: containers, entity: entity)
    }

    guard let moduleWord = cursor.readWord() else { return nil }
    module = moduleWord

    // Only the module remains: the module's own symbol. Leftover input that fails to parse
    // is a miss (D-06 fallback) — never mis-attribute the entity to the module symbol.
    if cursor.isAtEnd {
      return ParsedUSR(
        module: module, isSystemModule: false, containers: [], name: module, extendingModule: nil)
    }
    guard let entity = parseEntity(afterHead: &cursor, containers: &containers) else {
      return nil
    }
    return finish(module: module, isSystem: isSystem, containers: containers, entity: entity)
  }

  private struct Entity {
    let name: String
    /// True when the opaque tail carries a shape (local context, operator encoding) whose
    /// source name is not the parsed word — the caller falls back instead of mis-naming.
    let uninterpretedReaderTail: Bool
  }

  /// Reads the container chain and the final entity word after the head context. Returns nil
  /// when the shape is not one the parser understands (the caller then falls back per D-06).
  private static func parseEntity(
    afterHead cursor: inout Cursor, containers: inout [CanonicalSymbolFormatter.Container]
  ) -> Entity? {
    var extendingModule: String? = nil

    while !cursor.isAtEnd {
      // Constructor and destructor entities carry no name word in the USR: a label-less
      // `init()` is the container followed directly by an `A…cfc` argument region, and
      // `deinit` is the bare `fd` tail. The store kind supplies the Swift-native name
      // ("init"/"deinit"); the empty parsed name is valid only for those kinds (the mapper
      // rejects it for everything else).
      let remaining = cursor.remaining()
      if remaining.hasPrefix("A"), remaining.contains("cfc"), !containers.isEmpty {
        return Entity(name: "", uninterpretedReaderTail: false)
      }
      if remaining == "fd", !containers.isEmpty {
        return Entity(name: "", uninterpretedReaderTail: false)
      }

      if let substitution = cursor.peekSubstitution() {
        // A type substitution in context position names a container type.
        guard let resolved = stdlibSubstitution(substitution) else { return nil }
        cursor.consumeSubstitution()
        containers.append(resolved.container)
        continue
      }

      guard let word = cursor.readWord() else { return nil }

      if cursor.isAtEnd {
        // The signature region is absent only for context-ish USRs; treat the word as the
        // entity name with no tail.
        return Entity(name: word, uninterpretedReaderTail: false)
      }

      guard let next = cursor.peek() else { return nil }

      if next == "E" {
        // `<extending-module>E` marks a retroactive extension context: the word is the
        // declaring module, which never drives the canonical header (SYM-02).
        cursor.advance()
        if cursor.isAtEnd { return nil }
        extendingModule = word
        continue
      }

      if let kind = containerKind(for: next) {
        cursor.advance()
        containers.append(CanonicalSymbolFormatter.Container(name: word, kind: kind))
        continue
      }

      // Not a container: the word is the entity name and everything after it is the opaque
      // signature region (argument/local `A...` contexts included — the store kind corrects
      // the name for those: constructors/destructors use their Swift-native spelling,
      // parameters take the D-06 fallback via the kind map). An "oi" tail marks an operator
      // encoding whose source spelling is not the parsed word — fall back until the full
      // grammar pass covers operators.
      let tail = cursor.remaining()
      if tail.hasPrefix("oi") {
        return Entity(name: word, uninterpretedReaderTail: true)
      }
      return Entity(name: word, uninterpretedReaderTail: false)
    }

    // The chain ended on a container: the innermost container is the entity itself.
    guard let innermost = containers.popLast() else { return nil }
    _ = extendingModule
    return Entity(name: innermost.name, uninterpretedReaderTail: false)
  }

  private static func finish(
    module: String,
    isSystem: Bool,
    containers: [CanonicalSymbolFormatter.Container],
    entity: Entity
  ) -> ParsedUSR? {
    guard !entity.uninterpretedReaderTail else { return nil }
    return ParsedUSR(
      module: module, isSystemModule: isSystem, containers: containers, name: entity.name,
      extendingModule: nil)
  }

  /// Kind letters that may follow a word in container position.
  private static func containerKind(for character: Character) -> DeclKind? {
    switch character {
    case "V": return .struct
    case "C": return .class
    case "O": return .enum
    case "P": return .protocol
    case "a": return .typeAlias
    case "F", "f": return .func
    default: return nil
    }
  }

  private struct SubstitutedType {
    let container: CanonicalSymbolFormatter.Container
  }

  /// The stdlib substitutions the parser resolves; every other `S…` shape falls back (D-06).
  private static func stdlibSubstitution(_ letters: String) -> SubstitutedType? {
    switch letters {
    case "SS": return SubstitutedType(
      container: CanonicalSymbolFormatter.Container(name: "String", kind: .struct))
    case "Sd": return SubstitutedType(
      container: CanonicalSymbolFormatter.Container(name: "Double", kind: .struct))
    case "Si": return SubstitutedType(
      container: CanonicalSymbolFormatter.Container(name: "Int", kind: .struct))
    case "Sb": return SubstitutedType(
      container: CanonicalSymbolFormatter.Container(name: "Bool", kind: .struct))
    case "Sf": return SubstitutedType(
      container: CanonicalSymbolFormatter.Container(name: "Float", kind: .struct))
    case "Su": return SubstitutedType(
      container: CanonicalSymbolFormatter.Container(name: "UInt", kind: .struct))
    default: return nil
    }
  }

  /// A bounded, no-force-unwrap cursor over the USR's UTF-8 bytes.
  private struct Cursor {
    let scalars: [Character]
    var index = 0

    init(_ string: String) {
      self.scalars = Array(string)
    }

    var isAtEnd: Bool { index >= scalars.count }

    func peek() -> Character? {
      index < scalars.count ? scalars[index] : nil
    }

    mutating func advance() {
      index += 1
    }

    func remaining() -> String {
      String(scalars[min(index, scalars.count)...])
    }

    mutating func consume(prefix: String) -> Bool {
      let chars = Array(prefix)
      guard index + chars.count <= scalars.count else { return false }
      for (offset, char) in chars.enumerated() where scalars[index + offset] != char {
        return false
      }
      index += chars.count
      return true
    }

    /// Peeks an `S`-prefixed stdlib substitution (two characters) without consuming it.
    func peekSubstitution() -> String? {
      guard index + 1 < scalars.count, scalars[index] == "S" else { return nil }
      let second = scalars[index + 1]
      // A lowercase letter following 'S' begins a longer operator/word mangling the parser
      // does not resolve; only the two-letter stdlib set is recognized.
      return "S\(second)"
    }

    mutating func consumeSubstitution() {
      index += 2
    }

    /// Reads one length-prefixed word (`<decimal-length><word>`), validating the claimed
    /// length against the remaining input. Punycode (`00`-prefixed) words return nil — they
    /// are resolved by the full grammar pass, not this fast path.
    mutating func readWord() -> String? {
      var digits = ""
      while let next = peek(), next.isNumber, next.isASCII {
        digits.append(next)
        advance()
      }
      guard !digits.isEmpty, digits.count <= 4, let length = Int(digits) else { return nil }
      // Punycode words are introduced by a `00`-prefixed length; ordinary decimal lengths
      // never carry a leading zero.
      guard !digits.hasPrefix("0") else { return nil }
      guard scalars.count - index >= length, length > 0 else { return nil }
      let word = String(scalars[index..<(index + length)])
      guard word.allSatisfy(isWordCharacter) else { return nil }
      index += length
      return word
    }

    func isWordCharacter(_ character: Character) -> Bool {
      character.isASCII && (character.isLetter || character.isNumber) || character == "_"
    }
  }
}
