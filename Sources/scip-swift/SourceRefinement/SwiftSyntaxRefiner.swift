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

    tokenEndColumns = map
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
