/// Requirement: SYM-03 / D-05 — total Swift USR grammar parser (USR string -> ParsedUSR).
///
/// Parses compiler-emitted USRs directly (never via the demangler —
/// D-05 keeps `libswiftDemangle` display-only): the `s:` scheme prefix, the leading
/// module (length-prefixed) or stdlib substitution, the identifier+kind-letter container
/// chain (V struct, C class, O enum, P protocol, a typealias, F/f func), retroactive
/// extension `E` contexts (extended type + extending module marker), the final entity
/// name, and `0`-prefixed word-substituted identifiers (docs/ABI Mangling.rst: references
/// to words of previously mangled identifiers — this is how a retroactive extending module
/// that shares words with the extended type's module is encoded). The trailing signature
/// region is treated as opaque — skipped, never interpreted.
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
    /// True when the entity's mangling carries the operator encoding marker (`<word>oi…`):
    /// the parsed word is the operator's mangled letters, not its source spelling.
    let isOperator: Bool
  }

  /// Parses a USR. Returns nil on any miss — unparseable shapes, non-`s:` schemes, and
  /// truncated or adversarial input take the D-06 fallback path. Parameters (whose own names
  /// ride inside local-context `A...L_` manglings the grammar pass does not decode) also
  /// fall back in this phase.
  static func parse(_ usr: String) -> ParsedUSR? {
    // Module import USRs (SYM-04 / D-17, 03-03): the store surfaces each written
    // `import` / `@testable import` as a module occurrence whose USR is exactly
    // `c:@M@<ModuleName>`. The production is total for non-empty remainders; an empty
    // remainder stays a miss (D-06 fallback). It parses ONLY the name — whether the
    // module is repo-local (`swiftpm` header) or external (`swift` + pinned version)
    // is the caller's decision, supplied through the mapper's `isSystemLocation`
    // exactly like store-reported system locations.
    if usr.hasPrefix("c:@M@") {
      let name = String(usr.dropFirst("c:@M@".count))
      guard !name.isEmpty else { return nil }
      return ParsedUSR(
        module: name, isSystemModule: false, containers: [], name: name,
        extendingModule: nil, isOperator: false)
    }

    var cursor = Cursor(usr)
    guard cursor.consume(prefix: "s:") else { return nil }

    var module: String
    var isSystem = false
    var containers: [CanonicalSymbolFormatter.Container] = []

    // Swift-module implicit head (REL-01 / D-22, 04-02): the Swift module itself is
    // mangled as a bare lowercase `s` directly after the scheme —
    // `s:s23CustomStringConvertibleP` is Swift.CustomStringConvertible. Only an `s`
    // followed by a digit introduces it (the module word is always length-prefixed
    // there); any other shape falls through to the ordinary paths and misses when
    // unparseable. System-ness comes from the parse — stdlib protocols report
    // isSystem=false at their use sites, so the location can never supply the header.
    if cursor.peek() == "s", cursor.peek(at: 1).map({ $0.isNumber && $0.isASCII }) == true {
      cursor.advance()
      module = "Swift"
      isSystem = true
      if cursor.isAtEnd {
        return ParsedUSR(
          module: module, isSystemModule: isSystem, containers: [], name: module,
          extendingModule: nil, isOperator: false)
      }
      guard let entity = parseEntity(afterHead: &cursor, containers: &containers) else {
        return nil
      }
      return finish(module: module, isSystem: isSystem, containers: containers, entity: entity)
    }

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
          extendingModule: nil,
          isOperator: false
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
        module: module, isSystemModule: false, containers: [], name: module, extendingModule: nil,
        isOperator: false)
    }
    guard let entity = parseEntity(afterHead: &cursor, containers: &containers) else {
      return nil
    }
    return finish(module: module, isSystem: isSystem, containers: containers, entity: entity)
  }

  private struct Entity {
    let name: String
    /// True when the opaque tail carries a shape whose source name is not the parsed word —
    /// the caller falls back instead of mis-naming.
    let uninterpretedReaderTail: Bool
    /// The declaring module of a retroactive extension context, when the USR carries an `E`
    /// marker. Informational only — the canonical header always uses the extended type's
    /// owner module (SYM-02).
    let extendingModule: String?
    let isOperator: Bool

    init(
      name: String, uninterpretedReaderTail: Bool, extendingModule: String? = nil,
      isOperator: Bool = false
    ) {
      self.name = name
      self.uninterpretedReaderTail = uninterpretedReaderTail
      self.extendingModule = extendingModule
      self.isOperator = isOperator
    }
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
        return Entity(name: "", uninterpretedReaderTail: false, extendingModule: extendingModule)
      }
      if remaining == "fd", !containers.isEmpty {
        return Entity(name: "", uninterpretedReaderTail: false, extendingModule: extendingModule)
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
        return Entity(name: word, uninterpretedReaderTail: false, extendingModule: extendingModule)
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
      _ = extendingModule

      if let kind = containerKind(for: next) {
        cursor.advance()
        containers.append(CanonicalSymbolFormatter.Container(name: word, kind: kind))
        continue
      }

      // Not a container: the word is the entity name and everything after it is the opaque
      // signature region (argument/local `A...` contexts included — the store kind corrects
      // the name for those: constructors/destructors use their Swift-native spelling,
      // parameters take the D-06 fallback via the kind map). An "oi" tail marks an operator
      // encoding: the parsed word is the operator's mangled letters, not its source spelling
      // — the mapper re-derives the name from the store name (assumption A4), so the parse
      // stays valid with `isOperator` set.
      let isOperator = cursor.remaining().hasPrefix("oi")
      return Entity(
        name: word, uninterpretedReaderTail: false, extendingModule: extendingModule,
        isOperator: isOperator)
    }

    // The chain ended on a container: the innermost container is the entity itself.
    guard let innermost = containers.popLast() else { return nil }
    return Entity(
      name: innermost.name, uninterpretedReaderTail: false, extendingModule: extendingModule)
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
      extendingModule: entity.extendingModule, isOperator: entity.isOperator)
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

  /// The stdlib substitutions the parser resolves; every other `S…` shape falls back
  /// (D-06). The TYPE set is the frozen six (SS/Sd/Si/Sb/Sf/Su); the PROTOCOL set
  /// (REL-01 / D-22, 04-02) is enumerated empirically from the mangler — every
  /// two-letter `S<letter>` shape that resolves to a Swift-module PROTOCOL under
  /// `swift-demangle` (sweep of all 52 letters, pinned in USRSymbolParserTests corpus
  /// rows). Non-protocol substitutions (SA, SD, So, …) intentionally stay unresolved:
  /// the D-22 scope is protocol conformance edges, and an unresolved shape fails soft
  /// into the raw-USR Term (visible in diagnostics), never silently mis-named.
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
    // Protocols (04-02, D-22) — the empirically enumerated Swift-module set.
    case "SB": return protocolContainer("BinaryFloatingPoint")
    case "SE": return protocolContainer("Encodable")
    case "SF": return protocolContainer("FloatingPoint")
    case "SG": return protocolContainer("RandomNumberGenerator")
    case "SH": return protocolContainer("Hashable")
    case "SK": return protocolContainer("BidirectionalCollection")
    case "SL": return protocolContainer("Comparable")
    case "SM": return protocolContainer("MutableCollection")
    case "SQ": return protocolContainer("Equatable")
    case "ST": return protocolContainer("Sequence")
    case "SU": return protocolContainer("UnsignedInteger")
    case "SX": return protocolContainer("RangeExpression")
    case "SY": return protocolContainer("RawRepresentable")
    case "SZ": return protocolContainer("SignedInteger")
    case "Se": return protocolContainer("Decodable")
    case "Sj": return protocolContainer("Numeric")
    case "Sk": return protocolContainer("RandomAccessCollection")
    case "Sl": return protocolContainer("Collection")
    case "Sm": return protocolContainer("RangeReplaceableCollection")
    case "St": return protocolContainer("IteratorProtocol")
    case "Sx": return protocolContainer("Strideable")
    case "Sy": return protocolContainer("StringProtocol")
    case "Sz": return protocolContainer("BinaryInteger")
    default: return nil
    }
  }

  private static func protocolContainer(_ name: String) -> SubstitutedType {
    SubstitutedType(
      container: CanonicalSymbolFormatter.Container(name: name, kind: .protocol))
  }

  // MARK: - Punycode (docs/ABI Mangling.rst identifiers: `00<length><punycode>`)

  /// Swift mangles identifiers containing non-word characters (emoji, CJK, π) as punycode
  /// (RFC 3492) with one deviation: digits 26-35 render as `A`-`J` instead of `0`-`9`, so
  /// the encoded form never contains a decimal digit and the length prefix stays
  /// self-delimiting. Corpus: `004BFIh` -> 🚀, `003Bxa` -> π, `006ldrIFb` -> 名前.
  ///
  /// Total by construction (T-02-01): every arithmetic step is overflow-checked and every
  /// produced code point is range-checked; any miss returns nil into the D-06 fallback.
  private static func decodePunycodeWord(_ encoded: [Character]) -> String? {
    // A trailing-hyphen delimiter splits basic (literal ASCII) code points from the encoded
    // delta digits; without one the whole region is the encoded part.
    var basic: [UnicodeScalar] = []
    var digitScalars = encoded
    if let delimiter = encoded.lastIndex(of: "-") {
      for character in encoded[..<delimiter] {
        guard let ascii = character.asciiValue, isWordCharacterUnicode(ascii) else {
          return nil
        }
        basic.append(UnicodeScalar(ascii))
      }
      digitScalars = Array(encoded[(delimiter + 1)...])
    }

    var output = basic
    var n = 0x80
    var i = 0
    var bias = 72
    var index = 0
    while index < digitScalars.count {
      let oldi = i
      var w = 1
      var k = 36
      while true {
        guard index < digitScalars.count else { return nil }
        guard let digit = punycodeDigitValue(digitScalars[index]) else { return nil }
        index += 1

        let (product, overflow1) = digit.multipliedReportingOverflow(by: w)
        if overflow1 { return nil }
        let (sum, overflow2) = i.addingReportingOverflow(product)
        if overflow2 { return nil }
        i = sum

        let t = k <= bias ? 1 : (k >= bias + 26 ? 26 : k - bias)
        if digit < t { break }
        let (nextW, overflow3) = w.multipliedReportingOverflow(by: 36 - t)
        if overflow3 { return nil }
        w = nextW
        k += 36
        if k > 1_000_000 { return nil }
      }

      let outLength = output.count + 1
      let (delta, overflow4) = i.subtractingReportingOverflow(oldi)
      if overflow4 { return nil }
      bias = adaptPunycodeBias(delta: delta, numpoints: outLength, firstTime: oldi == 0)

      n += i / outLength
      guard n <= 0x10FFFF else { return nil }
      i %= outLength
      guard let scalar = UnicodeScalar(n) else { return nil }
      output.insert(scalar, at: i)
      i += 1
    }

    guard !output.isEmpty else { return nil }
    return String(String.UnicodeScalarView(output))
  }

  private static func punycodeDigitValue(_ character: Character) -> Int? {
    guard let ascii = character.asciiValue else { return nil }
    switch ascii {
    case UInt8(ascii: "a")...UInt8(ascii: "z"):
      return Int(ascii - UInt8(ascii: "a"))
    case UInt8(ascii: "A")...UInt8(ascii: "J"):
      return Int(ascii - UInt8(ascii: "A")) + 26
    default:
      return nil
    }
  }

  private static func adaptPunycodeBias(delta: Int, numpoints: Int, firstTime: Bool) -> Int {
    var delta = delta
    delta = firstTime ? delta / 700 : delta / 2
    delta += delta / numpoints
    var k = 0
    while delta > ((36 - 1) * 26) / 2 {
      delta /= 36 - 1
      k += 36
    }
    return k + ((36 - 1 + 1) * delta) / (delta + 38)
  }

  private static func isWordCharacterUnicode(_ ascii: UInt8) -> Bool {
    switch ascii {
    case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
      UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"):
      return true
    default:
      return false
    }
  }

  /// A bounded, no-force-unwrap cursor over the USR's UTF-8 bytes.
  private struct Cursor {
    let scalars: [Character]
    var index = 0
    /// The words of every identifier read so far in this USR, first-appearance order — the
    /// substitution table `0`-prefixed identifiers reference (docs/ABI Mangling.rst).
    var wordTable = WordTable()
    /// Peeks the character `offset` positions ahead (0 == `peek()`), nil past the end.
    func peek(at offset: Int) -> Character? {
      let target = index + offset
      return target < scalars.count ? scalars[target] : nil
    }

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
    /// length against the remaining input. `00`-prefixed lengths introduce a punycode word
    /// (`00<length><punycode>`), decoded in place; a bare leading `0` introduces a
    /// word-substituted identifier (`0<parts>`), decoded from the word table.
    mutating func readWord() -> String? {
      var digits = ""
      while let next = peek(), next.isNumber, next.isASCII {
        digits.append(next)
        advance()
      }
      guard !digits.isEmpty, digits.count <= 4 else { return nil }
      guard scalars.count - index > 0 else { return nil }

      if digits == "0" {
        let word = readSubstitutedWord()
        if let word { wordTable.addWords(of: word) }
        return word
      }

      guard let word = readLengthPrefixedSegment(digits: digits) else { return nil }
      wordTable.addWords(of: word)
      return word
    }

    /// Reads one `0`-prefixed word-substituted identifier (docs/ABI Mangling.rst): a
    /// sequence of word references — lowercase `a`-`z` for all but the final reference,
    /// uppercase for the final one — interleaved with length-prefixed literal segments,
    /// over the words of every identifier mangled so far in this USR. A final word
    /// reference with no literal after it is terminated by a literal `0`.
    ///
    /// An uppercase letter whose index names no mangled word is NOT part of the identifier
    /// (the retroactive `E` marker directly after the last segment is exactly such a
    /// letter), so the identifier ends there without consuming it. Known residual ambiguity
    /// (T-02-01 fail-soft): with five or more mangled words a marker letter can alias a
    /// valid reference index; such a USR mis-parses or misses into the D-06 fallback, never
    /// into a crash.
    private mutating func readSubstitutedWord() -> String? {
      var parts = ""
      while let next = peek() {
        if let ascii = next.asciiValue {
          if ascii >= UInt8(ascii: "a"), ascii <= UInt8(ascii: "z") {
            let index = Int(ascii - UInt8(ascii: "a"))
            guard index < wordTable.count else { return nil }
            parts += wordTable[index]
            advance()
            continue
          }
          if ascii >= UInt8(ascii: "A"), ascii <= UInt8(ascii: "Z") {
            let index = Int(ascii - UInt8(ascii: "A"))
            guard index < wordTable.count else { break }
            parts += wordTable[index]
            advance()
            continue
          }
        }
        if next.isNumber, next.isASCII {
          var digits = ""
          while let digit = peek(), digit.isNumber, digit.isASCII {
            digits.append(digit)
            advance()
          }
          if digits == "0" {
            // The grammar's terminator: a final word reference with no literal after it
            // (literal run-lengths never carry a leading zero, so a bare `0` cannot be one).
            break
          }
          guard digits.count <= 4, let literal = readLengthPrefixedSegment(digits: digits)
          else { return nil }
          parts += literal
          continue
        }
        break
      }
      guard !parts.isEmpty else { return nil }
      return parts
    }

    /// Reads the payload after a digit prefix: a plain length-prefixed word, or a punycode
    /// word when the prefix starts with `00`. Does not touch the word table — callers
    /// register the assembled identifier once.
    private mutating func readLengthPrefixedSegment(digits: String) -> String? {
      if digits.hasPrefix("00") {
        // Punycode word: the digits after `00` give the encoded length. The punycode output
        // alphabet (`a`-`z`, `A`-`J`) contains no digits, so the decimal length is
        // self-delimiting; ordinary word lengths never carry a leading zero.
        guard digits.count >= 3, let length = Int(digits.dropFirst(2)), length > 0,
          scalars.count - index >= length
        else { return nil }
        let encoded = Array(scalars[index..<(index + length)])
        index += length
        return USRSymbolParser.decodePunycodeWord(encoded)
      }

      guard let length = Int(digits) else { return nil }
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

  /// The word-substitution table for one USR (docs/ABI Mangling.rst): identifiers split at
  /// underscores and at an uppercase letter following a non-uppercase character; new words
  /// append in first-appearance order (the grammar caps substitution references at 26).
  private struct WordTable {
    private(set) var words: [String] = []

    var count: Int { words.count }

    subscript(index: Int) -> String {
      words[index]
    }

    mutating func addWords(of identifier: String) {
      var current = ""
      var previousWasUppercase = false

      func flush() {
        if !current.isEmpty, !words.contains(current) {
          words.append(current)
        }
        current = ""
      }

      for character in identifier {
        if character == "_" {
          flush()
          previousWasUppercase = false
          continue
        }
        let isUppercaseLetter = character.isASCII && character.isLetter && character.isUppercase
        if isUppercaseLetter, !previousWasUppercase, !current.isEmpty {
          flush()
        }
        current.append(character)
        previousWasUppercase = isUppercaseLetter
      }
      flush()
    }
  }
}
