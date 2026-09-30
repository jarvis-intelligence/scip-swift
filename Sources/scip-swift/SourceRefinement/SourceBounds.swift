import Foundation

/// UTF-8 line bounds, excluding line terminators. Endpoints must be scalar boundaries.
struct SourceBounds {
  private let lines: [[UInt8]]

  init(source: String) {
    lines = source.utf8.split(separator: 0x0A, omittingEmptySubsequences: false).map {
      var bytes = Array($0)
      if bytes.last == 0x0D { bytes.removeLast() }
      return bytes
    }
  }

  private func contains(line: Int, column: Int) -> Bool {
    guard lines.indices.contains(line), column >= 0, column <= lines[line].count else {
      return false
    }
    return column == lines[line].count || lines[line][column] & 0xC0 != 0x80
  }

  func contains(range: [Int32]) -> Bool {
    guard range.count == 4 else { return false }
    let values = range.map(Int.init)
    return contains(line: values[0], column: values[1])
      && contains(line: values[2], column: values[3])
      && (values[0] < values[2] || (values[0] == values[2] && values[1] < values[3]))
  }

  /// Drop invalid starts; clamp overlong ends to the line, never into a UTF-8 scalar.
  func validated(_ range: Scip_SingleLineRange) -> Scip_SingleLineRange? {
    let line = Int(range.line)
    let start = Int(range.startCharacter)
    guard contains(line: line, column: start) else { return nil }
    var end = min(Int(range.endCharacter), lines[line].count)
    while end > start && !contains(line: line, column: end) { end -= 1 }
    guard end > start else { return nil }
    var result = range
    result.endCharacter = Int32(end)
    return result
  }
}
