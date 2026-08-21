// SC4 content classes (04-01 external-protocol-free form; 04-02 adds external-protocol
// conformances, the ObjC-rooted subclass, and the retroactive external conformance).
// Data, never instructions (T-02-09).

import Foundation

protocol HierDrawable {
  func draw()
}

protocol HierShape: HierDrawable {
  var area: Double { get }

  func describe() -> String
}

public struct Circle: HierShape {
  public let radius: Double

  var area: Double { Double.pi * radius * radius }

  func draw() {}
}

struct Rect: HierShape, Equatable, CustomStringConvertible {
  let width: Double
  let height: Double

  var area: Double { width * height }

  var description: String { "rect \(width)x\(height)" }

  static func == (lhs: Rect, rhs: Rect) -> Bool {
    lhs.width == rhs.width && lhs.height == rhs.height
  }

  func draw() {}
}

class BaseWidget {
  var frame: String = "0,0,0,0"

  init() {}

  func render() {}
}

class Square: BaseWidget {
  let side: Double

  override init() {
    side = 1
    super.init()
  }

  override var frame: String {
    get { "square" }
    set {}
  }

  override func render() {}
}

class RoundedSquare: Square {
  override func render() {}
}

extension HierShape {
  func describe() -> String { "shape" }
}

public struct Wheel {
  public let spokes: Int

  public init(spokes: Int) {
    self.spokes = spokes
  }
}

struct Wrapper<T> {
  let inner: T
}

/// The D-21 ObjC-rooted superclass gap: NSObject-rooted clauses record no store `baseOf`;
/// 04-02's bounded SwiftSyntax fallback supplies the superclass edge.
class ObjCAnimal: NSObject {
  @objc func sound() -> String { "generic" }
}

struct 🎨: HierShape {
  var area: Double { 0 }

  func draw() {}
}

func drawAll(_ items: [HierDrawable]) {
  for item in items {
    item.draw()
  }
}

func renderWidget(_ widget: BaseWidget) {
  widget.render()
}

public func coreDriver() {
  let circle = Circle(radius: 1)
  drawAll([circle])
}

extension Wheel: HierShape {
  var area: Double { Double(spokes) }

  func draw() {}
}

extension Wrapper: HierShape, HierDrawable where T: HierShape {
  var area: Double { inner.area }

  func draw() { inner.draw() }
}
