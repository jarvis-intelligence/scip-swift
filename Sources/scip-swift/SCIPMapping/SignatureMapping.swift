import IndexStoreDB

/// Requirement: META-05 — reconstruct minimal Swift signatures from Symbol data.
///
/// Produces `Scip_Signature` messages with basic declaration prefixes (func, var, class, etc.)
/// from IndexStoreDB `Symbol.kind` and `Symbol.name`. These improve hover tooltips from bare
/// names to useful declarations like "func greet(name:)".
///
/// Limitation: signatures lack parameter types and return types — IndexStoreDB's `Symbol.name`
/// includes argument labels for methods (e.g. `greet(name:)`) but not types. Full type
/// signatures would need source-comment parsing or AST data.
enum SignatureMapping {
  static func signature(for symbol: Symbol) -> Scip_Signature? {
    guard let prefix = declarationPrefix(for: symbol) else { return nil }
    var sig = Scip_Signature()
    sig.language = "swift"
    sig.text = "\(prefix) \(symbol.name)"
    return sig
  }

  private static func declarationPrefix(for symbol: Symbol) -> String? {
    switch symbol.kind {
    case .instanceMethod, .function, .classMethod, .staticMethod:
      return symbol.kind == .classMethod || symbol.kind == .staticMethod ? "static func" : "func"
    case .instanceProperty, .classProperty, .staticProperty, .variable:
      return symbol.kind == .classProperty || symbol.kind == .staticProperty ? "static var" : "var"
    case .field:
      return "let"
    case .class:
      return "class"
    case .struct:
      return "struct"
    case .enum:
      return "enum"
    case .protocol:
      return "protocol"
    case .extension:
      return "extension"
    case .typealias:
      return "typealias"
    case .constructor:
      return "init"
    case .parameter, .module, .unknown, .using, .commentTag, .namespaceAlias,
         .concept, .conversionFunction, .destructor, .enumConstant, .macro,
         .namespace, .union:
      return nil
    }
  }
}
