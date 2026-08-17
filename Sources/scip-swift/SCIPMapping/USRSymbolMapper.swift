import IndexStoreDB

/// Requirement: SYM-03 — the frozen Phase-1 declaration-kind families (22 values, ported from
/// `swift/internal/symbol/scheme.go`) that drive canonical descriptor suffixes.
enum DeclKind {
  case module
  case `struct`
  case `class`
  case `enum`
  case `protocol`
  case typeAlias
  case `func`
  case method
  case `operator`
  case constructor
  case destructor
  case getter
  case setter
  case property
  case constant
  case variable
  case `subscript`
  case enumCase
  case protocolMethod
  case typeParameter
  case parameter
  case macro
}

/// Requirement: SYM-03 — maps a parsed USR plus the IndexStoreDB `Symbol` (kind/subKind and
/// short name) onto the canonical scip-swift symbol string via `CanonicalSymbolFormatter`.
///
/// The declaration kind comes from the IndexStoreDB kind/subKind (never from the mangling's
/// type abbreviations), the identity (module, containers, name) comes from the USR, and the
/// module header is derived from the USR's owning module — `swiftpm` with version "." for
/// target modules, `swift` with the pinned toolchain version for system modules — never from
/// `location.moduleName`, which reports the declaring module for retroactive extension
/// members (SYM-02).
///
/// Fail-soft per D-06: when the parser cannot handle a USR (or the store kind has no canonical
/// family), the caller emits the raw USR as a single Term descriptor under the canonical module
/// header and records it in `SymbolMappingDiagnostics` — indexing never fails or drops a symbol.
enum USRSymbolMapper {
  /// Maps one symbol to its canonical string, or nil when the USR/kind combination must take
  /// the D-06 raw-USR fallback.
  static func canonicalSymbolString(
    parsed: USRSymbolParser.ParsedUSR,
    symbol: Symbol,
    isSystemLocation: Bool,
    toolchainVersion: String,
    overloadIndex: Int = 0
  ) -> String? {
    guard var kind = declKind(for: symbol), var name = sourceName(parsed: parsed, symbol: symbol)
    else { return nil }

    // Operators (assumption A4): the mangling stores the operator's mangled letters, not its
    // source spelling. Operator-ness is the `oi` mangling marker on the parsed USR plus the
    // store name's shape (a non-simple-identifier spelling); "+" — inside the identifier
    // charset — is caught by the marker alone. The spelling is the store name up to its
    // argument list; escaping stays the formatter's job. A marker without a usable spelling
    // falls back rather than emitting the mangled letters as a name.
    if kind == .func || kind == .method, parsed.isOperator {
      guard let spelling = operatorSpelling(fromStoreName: symbol.name) else { return nil }
      kind = .operator
      name = spelling
    } else if kind == .func || kind == .method,
      let spelling = operatorSpelling(fromStoreName: symbol.name),
      spelling.contains { !CanonicalSymbolFormatter.isIdentifierCharacter($0) }
    {
      kind = .operator
      name = spelling
    }

    let input = CanonicalSymbolFormatter.SymbolInput(
      module: parsed.module,
      isSystemModule: parsed.isSystemModule || isSystemLocation,
      swiftToolchainVersion: toolchainVersion,
      containerPath: parsed.containers,
      name: name,
      kind: kind,
      overloadIndex: overloadIndex
    )
    return CanonicalSymbolFormatter.symbol(input)
  }

  /// The operator spelling from an IndexStoreDB short name ("==(_:_:)" -> "==", "+(A:B:)" ->
  /// "+"), or nil when there is nothing before the argument list. Note "+" is itself inside
  /// the simple-identifier set — the `oi` mangling marker on the parsed USR is what marks the
  /// entity as an operator; the shape check only supplements it.
  static func operatorSpelling(fromStoreName storeName: String) -> String? {
    let spelling = storeName.firstIndex(of: "(").map { String(storeName[..<$0]) } ?? storeName
    return spelling.isEmpty ? nil : spelling
  }

  /// The frozen kind families for store kinds the scheme defines; store kinds with no family
  /// (unknown, parameters whose own USR the parser does not expose, comments…) return nil and
  /// take the D-06 fallback.
  static func declKind(for symbol: Symbol) -> DeclKind? {
    switch symbol.subKind {
    case .swiftAccessorAddressor:
      return .getter
    case .accessorGetter:
      return .getter
    case .accessorSetter, .swiftAccessorWillSet, .swiftAccessorDidSet,
      .swiftAccessorMutableAddressor:
      return .setter
    case .swiftSubscript:
      return .subscript
    default:
      break
    }

    switch symbol.kind {
    case .module:
      return .module
    case .struct:
      return .struct
    case .class:
      return .class
    case .enum:
      return .enum
    case .protocol:
      return .protocol
    case .typealias:
      return .typeAlias
    case .extension:
      // An extension declaration rides the extended type's own USR; it renders as the
      // extended type (a Type descriptor), matching SYM-02's "as if declared inside the
      // type body" rule.
      return .struct
    case .function:
      return .func
    case .instanceMethod, .classMethod, .staticMethod:
      return .method
    case .conversionFunction:
      return .method
    case .constructor:
      return .constructor
    case .destructor:
      return .destructor
    case .instanceProperty, .classProperty, .staticProperty:
      return .property
    case .field:
      return .property
    case .variable:
      return .variable
    case .enumConstant:
      return .enumCase
    case .macro:
      return .macro
    case .unknown, .using, .commentTag, .namespace, .namespaceAlias, .union, .parameter,
      .concept:
      return nil
    }
  }

  /// The source name the canonical descriptor carries. The USR's own word is authoritative for
  /// ordinary declarations; kinds whose source name the USR does not spell (constructors,
  /// destructors) use the Swift-native spelling, and setters carry the synthesized `name=`
  /// form (assumption A5).
  static func sourceName(parsed: USRSymbolParser.ParsedUSR, symbol: Symbol) -> String? {
    switch symbol.kind {
    case .constructor:
      return "init"
    case .destructor:
      return "deinit"
    default:
      break
    }
    switch symbol.subKind {
    case .accessorSetter, .swiftAccessorWillSet, .swiftAccessorDidSet,
      .swiftAccessorMutableAddressor:
      return parsed.name.isEmpty ? nil : "\(parsed.name)="
    default:
      return parsed.name
    }
  }
}

/// Requirement: SYM-03 / D-06 — per-run accounting of symbols emitted through the raw-USR
/// fallback, surfaced in diagnostics at build end. A class (not the stateless enum-namespace
/// mapper convention) because it accumulates state across the whole `build()` run, mirroring
/// `USRDemangler`'s memoization rationale.
///
/// Diagnostics discipline (ASVS V8): records code identifiers (USRs) only — never file paths
/// or user data — and caps the example list at five entries.
final class SymbolMappingDiagnostics {
  static let exampleLimit = 5

  private(set) var fallbackCount = 0
  private var fallbackExamples: [String] = []

  func recordFallback(usr: String) {
    fallbackCount += 1
    if fallbackExamples.count < Self.exampleLimit {
      fallbackExamples.append(usr)
    }
  }

  /// Human-readable summary, or nil when every symbol mapped canonically (silent success —
  /// ordinary runs print nothing).
  var summary: String? {
    guard fallbackCount > 0 else { return nil }
    let examples = fallbackExamples.joined(separator: ", ")
    return
      "\(fallbackCount) symbol(s) emitted via the raw-USR fallback (unparseable USRs); first \(Self.exampleLimit): \(examples)"
  }
}
