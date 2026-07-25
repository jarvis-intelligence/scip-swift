import IndexStoreDB

/// Requirement: IndexStoreDB to SCIP protobuf conversion — `Symbol.kind` mapping (task 3.4).
///
/// SCIP's `SymbolInformation.Kind` enum is a superset covering many languages; where Swift has no
/// exact counterpart (e.g. `destructor`, `conversionFunction`, C++-only `using`) this maps to the
/// closest reasonable kind rather than `unspecifiedKind`, except where nothing reasonable exists.
enum SymbolKindMapping {
  static func scipKind(for symbol: Symbol) -> Scip_SymbolInformation.Kind {
    switch symbol.subKind {
    case .swiftSubscript:
      return .subscript
    case .accessorGetter, .swiftAccessorAddressor:
      return .getter
    case .accessorSetter, .swiftAccessorWillSet, .swiftAccessorDidSet, .swiftAccessorMutableAddressor:
      return .setter
    default:
      break
    }

    switch symbol.kind {
    case .unknown, .using, .commentTag:
      return .unspecifiedKind
    case .module:
      return .module
    case .namespace, .namespaceAlias:
      return .namespace
    case .macro:
      return .macro
    case .enum:
      return .enum
    case .struct:
      return .struct
    case .class:
      return .class
    case .protocol:
      return .protocol
    case .extension:
      return .extension
    case .union:
      return .union
    case .typealias:
      return .typeAlias
    case .function:
      return .function
    case .variable:
      return .variable
    case .field:
      return .field
    case .enumConstant:
      return .enumMember
    case .instanceMethod:
      return .method
    case .classMethod, .staticMethod:
      return .staticMethod
    case .instanceProperty:
      return .property
    case .classProperty, .staticProperty:
      return .staticProperty
    case .constructor:
      return .constructor
    case .destructor, .conversionFunction:
      return .method
    case .parameter:
      return .parameter
    case .concept:
      return .concept
    }
  }
}
