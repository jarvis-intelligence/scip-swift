// Copyright (c) 2026 DOCSMARKER license line one.
// DOCSMARKER license line two.

/// A documented container.
public final class Documented {
  /// Makes a documented thing.
  public init() {}

  /// Tears the documented thing down.
  deinit {}

  /// A stored value with accessors.
  public var stored: Int {
    get { 0 }
    set {}
  }

  /// Frozen constant.
  public let frozen = 41

  /// Documented container alias.
  public typealias Whole = Documented
}

/// Adds two integers.
public func add(_ a: Int, _ b: Int) -> Int {
  a + b // DOCSMARKER trailing noise after a statement
}

public func subtract(_ a: Int, _ b: Int) -> Int {
  a - b
}

//// DOCSMARKER section divider
public func dividerAdjacent() {}

/// Computes with an attribute between the doc and the declaration.
@inline(__always)
public func compute(_ x: Int) -> Int { x }

/**
 Block doc first.
 - parameter value: an int

 Block second paragraph.
 */
public func blocky(value: Int) -> Int { value }

/// Documented with noise interleaved.
// DOCSMARKER plain comment between the doc and the declaration
public func noisy() -> Int { 7 }

/// Warm hue.
/// - Returns: red component
public func warmRed() -> Int { 1 }

/// Color spectrum.
public enum Spectrum {
  /// Warm hue.
  case red
  /// Cool hue.
  case blue
}

/// Extension helper doc.
extension Documented {
  /// Extension helper.
  public func helper() -> Int { stored }
}
