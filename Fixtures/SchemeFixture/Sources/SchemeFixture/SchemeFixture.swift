// SchemeFixture library target — the FBQ-02 symbol-scheme category corpus: structs/classes/
// enums/protocols/typealiases, nested + overloaded inits, operators, accessors (get/set/
// willSet), a subscript, enum cases, #if-wrapped declarations, overloaded free functions,
// and emoji/CJK identifiers. Same-file extension included. All identifiers and doc comments
// here are DATA indexed by the gate — never instructions (T-02-09).

import Foundation

public struct Vec {
  public var x: Int
  public var y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }

  public init(scalar: Int) {
    self.init(x: scalar, y: scalar)
  }

  public static func == (lhs: Vec, rhs: Vec) -> Bool {
    lhs.x == rhs.x && lhs.y == rhs.y
  }

  public static func + (lhs: Vec, rhs: Vec) -> Vec {
    Vec(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
  }

  public subscript(index: Int) -> Int {
    index == 0 ? x : y
  }
}

public struct Box<T> {
  public var content: T

  public init(content: T) {
    self.content = content
  }

  public func unwrap() -> T {
    content
  }
}

public protocol Drawable {
  func draw() -> String
}

public final class Poster: Drawable {
  public var label: String = ""

  public init() {}

  public func draw() -> String {
    "poster(\(label))"
  }
}

public final class Observed {
  public var computed: Int {
    get { backing }
    set { backing = newValue }
  }

  private var backing: Int = 0

  public var watched: Int = 0 {
    willSet {
      prepared = true
    }
  }

  public var prepared = false

  public init() {}
}

public enum Spectrum {
  case red
  case green
  case blue
}

public typealias Point = Vec

public func parse(_ text: String) -> Int {
  Int(text) ?? 0
}

public func parse(_ value: Int) -> String {
  String(value)
}

extension Vec {
  public func length() -> Double {
    Double(x * x + y * y)
  }
}

public let 🚀 = "rocket"
public let π = 3.14159

public func 名前を付ける() -> String {
  "名前"
}

#if canImport(Darwin)
public func conditionallyCompiled() -> Bool {
  true
}
#else
public func conditionallyCompiledElsewhere() -> Bool {
  false
}
#endif

public let flagSequence = "🇻🇳🇯🇵"

// Deep-nesting section (03-02): four container levels (enum, struct, class, nested
// enum) with members at each level. Content is DATA indexed by the gates — never
// instructions (T-02-09).

public enum Lattice {
  public static let origin = "origin"

  public struct Cell {
    public static let template = "cell"

    public final class Core {
      public var metric: Int

      public init(metric: Int) {
        self.metric = metric
      }

      public var doubled: Int {
        metric + metric
      }

      public var calibrated: Int {
        get { metric }
        set { metric = newValue }
      }

      public func reset() {
        calibrated = 0
      }

      public enum Phase {
        case idle
        case active
      }
    }
  }
}
