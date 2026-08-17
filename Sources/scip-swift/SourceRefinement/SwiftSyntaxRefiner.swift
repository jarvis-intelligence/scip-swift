import Foundation
import SwiftParser
import SwiftSyntax

/// Requirement: exact occurrence end columns from a single SwiftSyntax parse per file
/// (RANGE-01..03) — refines IndexStoreDB's anchor-only occurrences to real token extents.
///
/// IndexStoreDB decides WHAT the occurrences are; this refiner refines WHERE they end. A miss is
/// never an error: `exactEndColumn` returns nil and callers fall back to the existing
/// name-length approximation (research D2).
struct SwiftSyntaxRefiner {
  private let tokenEndColumns: [Int: [Int: Int]]
  private let docComments: [Int: [Int: String]]
  private let source: String
  private let syntaxTree: SourceFileSyntax

  init?(filePath: String) {
    guard let source = try? String(contentsOfFile: filePath, encoding: .utf8) else { return nil }

    let bytes = Array(source.utf8)
    var lineStarts = [0]
    for (index, byte) in bytes.enumerated() where byte == 0x0A {
      lineStarts.append(index + 1)
    }

    let tree = Parser.parse(source: source)
    var map: [Int: [Int: Int]] = [:]
    for token in tree.tokens(viewMode: .sourceAccurate) {
      let start = token.positionAfterSkippingLeadingTrivia.utf8Offset
      // endPosition includes trailing trivia, which would over-extend every token by the
      // whitespace that follows it; the identifier extent is start + byte length.
      let end = start + token.text.utf8.count
      let line = Self.line(ofOffset: start, lineStarts: lineStarts)
      let lineStart = lineStarts[line - 1]
      map[line, default: [:]][start - lineStart] = end - lineStart
    }

    var docs: [Int: [Int: String]] = [:]
    for decl in Self.declarations(in: Syntax(tree)) {
      guard let first = decl.firstToken(viewMode: .sourceAccurate),
        let doc = Self.docComment(from: first.leadingTrivia)
      else { continue }
      for nameToken in Self.nameTokens(of: decl) {
        let position = nameToken.positionAfterSkippingLeadingTrivia
        let line = Self.line(ofOffset: position.utf8Offset, lineStarts: lineStarts)
        let lineStart = lineStarts[line - 1]
        docs[line, default: [:]][position.utf8Offset - lineStart] = doc
      }
    }

    tokenEndColumns = map
    docComments = docs
    self.source = source
    self.syntaxTree = tree
  }

  /// IndexStoreDB reports 1-based `line` / 1-based UTF-8 byte `utf8Column`; the map is keyed
  /// 0-based, so the column shifts by one on lookup. A nil result means "no token starts at
  /// this anchor" — the caller must fall back, never fail.
  func exactEndColumn(line: Int, utf8Column: Int) -> Int? {
    guard line >= 1, utf8Column >= 1 else { return nil }
    return tokenEndColumns[line]?[utf8Column - 1]
  }

  /// Same lookup contract as `exactEndColumn`: 1-based IndexStoreDB inputs over the 0-based
  /// map, nil on miss.
  func documentation(line: Int, utf8Column: Int) -> String? {
    guard line >= 1, utf8Column >= 1 else { return nil }
    return docComments[line]?[utf8Column - 1]
  }

  private static func declarations(in node: Syntax) -> [DeclSyntax] {
    var result: [DeclSyntax] = []
    for child in node.children(viewMode: .sourceAccurate) {
      if let decl = child.as(DeclSyntax.self) {
        result.append(decl)
      } else {
        result.append(contentsOf: declarations(in: child))
      }
    }
    return result
  }

  private static func nameTokens(of decl: DeclSyntax) -> [TokenSyntax] {
    if let named = decl.asProtocol(NamedDeclSyntax.self) {
      return [named.name]
    }
    if let variable = decl.as(VariableDeclSyntax.self) {
      return variable.bindings.compactMap { binding in
        binding.pattern.as(IdentifierPatternSyntax.self)?.identifier
      }
    }
    if let initializer = decl.as(InitializerDeclSyntax.self) {
      return [initializer.initKeyword]
    }
    if let deinitializer = decl.as(DeinitializerDeclSyntax.self) {
      return [deinitializer.deinitKeyword]
    }
    if let extensionDecl = decl.as(ExtensionDeclSyntax.self) {
      if let first = extensionDecl.extendedType.firstToken(viewMode: .sourceAccurate) {
        return [first]
      }
    }
    if let enumCase = decl.as(EnumCaseDeclSyntax.self) {
      return enumCase.elements.map(\.name)
    }
    return []
  }

  /// Doc trivia attaches to the declaration's first token (an attribute list intercepts it),
  /// while IndexStoreDB definition anchors land on the name token — keying the doc map at first
  /// tokens would miss every attributed declaration.
  private static func docComment(from trivia: Trivia) -> String? {
    var lines: [String] = []
    for piece in trivia {
      switch piece {
      case .docLineComment(let text):
        let content = text.hasPrefix("///") ? String(text.dropFirst(3)) : text
        if content.hasPrefix("/") { continue }
        lines.append(Self.stripOneLeadingSpace(content))
      case .docBlockComment(let text):
        lines.append(contentsOf: Self.blockLines(text))
      default:
        continue
      }
    }
    return lines.isEmpty ? nil : lines.joined(separator: "\n")
  }

  private static func blockLines(_ text: String) -> [String] {
    guard text.hasPrefix("/**"), text.hasSuffix("*/") else { return [] }
    let body = String(text.dropFirst(3).dropLast(2))
    return body
      .components(separatedBy: "\n")
      .dropFirst(text.dropFirst(3).hasPrefix("\n") ? 1 : 0)
      .dropLast(text.dropFirst(3).dropLast(2).hasSuffix("\n") ? 1 : 0)
      .map { line in
        var stripped = line
        if stripped.hasPrefix(" ") { stripped = String(stripped.dropFirst()) }
        if stripped.hasPrefix("*") { stripped = String(stripped.dropFirst()) }
        return stripOneLeadingSpace(stripped)
      }
  }

  private static func stripOneLeadingSpace(_ content: String) -> String {
    if content.hasPrefix(" ") { return String(content.dropFirst()) }
    return content
  }

  private static func line(ofOffset offset: Int, lineStarts: [Int]) -> Int {
    var low = 0
    var high = lineStarts.count - 1
    while low < high {
      let mid = (low + high + 1) / 2
      if lineStarts[mid] <= offset {
        low = mid
      } else {
        high = mid - 1
      }
    }
    return low + 1
  }
}
