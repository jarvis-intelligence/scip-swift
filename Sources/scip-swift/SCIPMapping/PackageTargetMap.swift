import Foundation
import SwiftParser
import SwiftSyntax

/// Requirement: SYM-04 / NAV-03 (D-17 / D-18, 03-03) — the Package.swift target map.
///
/// One fail-soft SwiftSyntax pass over the indexed repo's `Package.swift`, producing
/// {targetName → kind (target | testTarget)} plus each target's source path. The SAME
/// map serves two seams in `SCIPIndexBuilder`:
/// - SYM-04 / D-17: the import-symbol manager form — a module named in the target list
///   is repo-local (`scip-swift swiftpm <Module> . <Module>/`); everything else is
///   external (`scip-swift swift <Module> <pin> <Module>/`).
/// - NAV-03 / D-18: test-document detection — a document whose relativePath falls under
///   a `.testTarget`'s path (or whose store moduleName names a test target) is a
///   test-target document and every occurrence it emits carries the Test bit. This
///   path/target detection is the PRIMARY mechanism: the store's
///   `SymbolProperty.unitTest` is empirically dead for SwiftPM + Swift Testing targets
///   (03-RESEARCH Q4) and stays only as a belt in `SymbolRoleMapping`.
///
/// Membership signal (NAV-03, chosen at RED time per 03-03 Task 4): PRIMARY =
/// relativePath prefix under a test target's declared (or default `Tests/<name>`) path;
/// SECONDARY = the document's store `location.moduleName` names a test target, applied
/// when path membership is inconclusive. Both defensible per research; both asserted in
/// `TestTargetMarkingTests`.
///
/// The manifest content is DATA, never instructions (canary discipline, T-02-09): the
/// parse is purely syntactic — it extracts `.target`/`.testTarget` call names and paths
/// and never evaluates anything. Fail-soft everywhere: a missing, unreadable, or
/// unparseable manifest yields nil from the factory; a parseable manifest with no
/// recognized targets yields an empty map. Nothing here throws.
struct PackageTargetMap {
  enum TargetKind: Equatable {
    case target
    case testTarget
  }

  private let targetsByName: [String: TargetKind]
  /// Source path of every declared target, normalized WITHOUT a trailing slash
  /// (e.g. "Sources/SchemeFixture", "Tests/SchemeFixtureTests").
  private let pathsByTarget: [String: String]

  var isEmpty: Bool { targetsByName.isEmpty }

  init(targetsByName: [String: TargetKind], pathsByTarget: [String: String]) {
    self.targetsByName = targetsByName
    self.pathsByTarget = pathsByTarget
  }

  /// Parses `<packageDirectory>/Package.swift`. Returns nil when the manifest is missing
  /// or unreadable; an empty (but non-nil) map when it holds no recognized targets.
  init?(packageDirectory: String) {
    let manifestPath = (packageDirectory as NSString).appendingPathComponent("Package.swift")
    guard let source = try? String(contentsOfFile: manifestPath, encoding: .utf8) else {
      return nil
    }
    self.init(manifestSource: source)
  }

  /// Parses manifest source text directly (the unit-tested seam). Any parse miss simply
  /// finds no targets — never an error.
  init(manifestSource: String) {
    let tree = Parser.parse(source: manifestSource)
    var targetsByName: [String: TargetKind] = [:]
    var pathsByTarget: [String: String] = [:]

    for call in Self.functionCalls(in: Syntax(tree)) {
      guard let (kind, name) = Self.targetKindAndName(of: call) else { continue }
      targetsByName[name] = kind
      pathsByTarget[name] = Self.path(of: call, kind: kind, name: name)
    }

    self.targetsByName = targetsByName
    self.pathsByTarget = pathsByTarget
  }

  /// True when `moduleName` names any declared target (library or test) — the SYM-04
  /// manager decision: repo-local target ⇒ `swiftpm`, else `swift` + pin.
  func containsTarget(named moduleName: String) -> Bool {
    targetsByName[moduleName] != nil
  }

  /// True when `moduleName` names a declared `.testTarget`.
  func isTestTarget(named moduleName: String) -> Bool {
    targetsByName[moduleName] == .testTarget
  }

  /// NAV-03 membership: PRIMARY = `relativePath` falls under a `.testTarget`'s path;
  /// SECONDARY = the document's store `moduleName` (uniform per document, empirically)
  /// names a test target — applied when path membership is inconclusive.
  func isTestTargetDocument(relativePath: String, moduleName: String? = nil) -> Bool {
    for (name, kind) in targetsByName where kind == .testTarget {
      let prefix = pathsByTarget[name] ?? Self.defaultPath(kind: .testTarget, name: name)
      if relativePath == prefix || relativePath.hasPrefix(prefix + "/") {
        return true
      }
    }
    if let moduleName {
      return isTestTarget(named: moduleName)
    }
    return false
  }

  // MARK: - SwiftSyntax extraction (syntactic only — manifest content is data)

  /// All `FunctionCallExprSyntax` nodes in the tree, in source order (small recursive
  /// walk; manifests are tiny).
  private static func functionCalls(in node: Syntax) -> [FunctionCallExprSyntax] {
    var result: [FunctionCallExprSyntax] = []
    for child in node.children(viewMode: .sourceAccurate) {
      if let call = child.as(FunctionCallExprSyntax.self) {
        result.append(call)
      }
      result.append(contentsOf: functionCalls(in: child))
    }
    return result
  }

  /// `.target(name: "...")` / `.testTarget(name: "...")` — the implicit-member call
  /// shape every manifest uses inside `Package(targets: [...])`.
  private static func targetKindAndName(
    of call: FunctionCallExprSyntax
  ) -> (kind: TargetKind, name: String)? {
    guard let member = call.calledExpression.as(MemberAccessExprSyntax.self),
      member.base == nil,
      let name = stringLiteral(argument: "name", of: call)
    else { return nil }
    switch member.declName.baseName.tokenKind {
    case .identifier("target"):
      return (.target, name)
    case .identifier("testTarget"):
      return (.testTarget, name)
    default:
      return nil
    }
  }

  private static func stringLiteral(argument label: String, of call: FunctionCallExprSyntax) -> String? {
    for argument in call.arguments {
      guard let argumentLabel = argument.label, argumentLabel.text == label,
        let literal = argument.expression.as(StringLiteralExprSyntax.self),
        literal.segments.count == 1,
        let segment = literal.segments.first?.as(StringSegmentSyntax.self)
      else { continue }
      return segment.content.text
    }
    return nil
  }

  /// The declared `path:` argument when present; otherwise the kind's default
  /// (`Sources/<name>` / `Tests/<name>`).
  private static func path(of call: FunctionCallExprSyntax, kind: TargetKind, name: String) -> String {
    if let declared = stringLiteral(argument: "path", of: call), !declared.isEmpty {
      return declared
    }
    return defaultPath(kind: kind, name: name)
  }

  private static func defaultPath(kind: TargetKind, name: String) -> String {
    switch kind {
    case .target: return "Sources/\(name)"
    case .testTarget: return "Tests/\(name)"
    }
  }
}
