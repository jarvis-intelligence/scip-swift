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
    guard let kind = declKind(for: symbol), let name = sourceName(parsed: parsed, symbol: symbol)
    else { return nil }

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
