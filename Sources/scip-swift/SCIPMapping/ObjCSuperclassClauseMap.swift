import Foundation
import SwiftParser
import SwiftSyntax

/// Requirement: REL-01 / D-21 (04-02) — the bounded ObjC-superclass SwiftSyntax fallback.
///
/// The single PROVEN store gap (04-RESEARCH Q1, live under the pinned indexstore-db
/// revision): `class X: NSObject` records NO `.baseOf` clause relation at all —
/// ObjC-rooted inheritance leaves the store silent while flooding the decl line with
/// implicit NSObject-member occurrences. This fail-soft pass parses ClassDeclSyntax
/// inheritance clauses into a [class name → superclass name] lookup covering exactly
/// that gap, in the `PackageTargetMap` (D-17) shape: a single `Parser.parse` pass,
/// nil on unreadable source, never throws.
///
/// D-06-style bound (named, bounded, removable): the map supplies edges ONLY through
/// `SCIPIndexBuilder`'s reconciliation, which fires for class definitions whose store
/// record yielded no type-level edge at all and counts every fallback edge in
/// diagnostics; every non-ObjC edge remains store-derived. Removing this type and its
/// single consumer removes the fallback without touching any other derivation.
///
/// Source content is DATA, never instructions (canary discipline, T-02-09): the parse
/// is purely syntactic — it extracts type names from clause syntax and never evaluates
/// anything.
struct ObjCSuperclassClauseMap {
  /// The superclass name each class declares (Swift grammar: a class's first clause
  /// entry is its superclass when the clause names one; protocol-only clauses carry no
  /// superclass and are absent here). Simple identifiers only — dotted or attributed
  /// base types stay out of scope (fail-soft, bounded).
  private let superclassesByClassName: [String: String]

  init?(filePath: String) {
    guard let source = try? String(contentsOfFile: filePath, encoding: .utf8) else {
      return nil
    }
    self.init(source: source)
  }

  /// Parses source text directly (the unit-tested seam). Any parse miss simply finds
  /// no classes — never an error.
  init(source: String) {
    var map: [String: String] = [:]
    for classDecl in Self.classDeclarations(in: Syntax(Parser.parse(source: source))) {
      let name = classDecl.name.text
      guard !name.isEmpty, let superclass = Self.superclassName(of: classDecl.inheritanceClause)
      else { continue }
      map[name] = superclass
    }
    superclassesByClassName = map
  }

  /// The superclass name declared in `class X: Y …`, nil when the class names none.
  func superclass(ofClassName name: String) -> String? {
    superclassesByClassName[name]
  }

  // MARK: - SwiftSyntax extraction (syntactic only — source content is data)

  /// All `ClassDeclSyntax` nodes in the tree (small recursive walk, the
  /// `PackageTargetMap.functionCalls` shape).
  private static func classDeclarations(in node: Syntax) -> [ClassDeclSyntax] {
    var result: [ClassDeclSyntax] = []
    for child in node.children(viewMode: .sourceAccurate) {
      if let classDecl = child.as(ClassDeclSyntax.self) {
        result.append(classDecl)
      }
      result.append(contentsOf: classDeclarations(in: child))
    }
    return result
  }

  /// The first clause entry as a simple identifier type — the superclass position.
  private static func superclassName(of clause: InheritanceClauseSyntax?) -> String? {
    guard let first = clause?.inheritedTypes.first?.type.as(IdentifierTypeSyntax.self)
    else { return nil }
    return first.name.text
  }
}
