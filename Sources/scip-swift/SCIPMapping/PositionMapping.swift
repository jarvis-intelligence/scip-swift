import IndexStoreDB

/// Requirement: IndexStoreDB to SCIP protobuf conversion — `SymbolOccurrence.location` mapping
/// (task 3.5).
///
/// IndexStoreDB (like the underlying IndexStore format itself) only records a single anchor point
/// per occurrence — 1-based line, 1-based UTF-8-byte column — not a start/end range. SCIP ranges
/// are half-open `[start, end)` and 0-based. This converts the anchor point to 0-based and
/// approximates the end column using the symbol's display name length (stopping at the first `(`
/// for compound Swift names like `greet(name:)`, since only the base name `greet` is highlighted
/// at the occurrence). This is a best-effort approximation, not an exact spelling range — see
/// README "Known limitations".
enum PositionMapping {
  static func singleLineRange(location: SymbolLocation, displayName: String) -> Scip_SingleLineRange {
    let zeroBasedLine = Int32(location.line - 1)
    let zeroBasedStartCharacter = Int32(location.utf8Column - 1)
    let length = Int32(approximateTokenLength(displayName: displayName))

    var range = Scip_SingleLineRange()
    range.line = max(zeroBasedLine, 0)
    range.startCharacter = max(zeroBasedStartCharacter, 0)
    range.endCharacter = range.startCharacter + max(length, 0)
    return range
  }

  private static func approximateTokenLength(displayName: String) -> Int {
    displayName.prefix(while: { $0 != "(" }).utf8.count
  }
}
