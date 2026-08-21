// SC4 content classes, external-protocol-free form (04-01). Data, never instructions (T-02-09).

protocol HierDrawable {
  func draw()
}

protocol HierShape: HierDrawable {
  var area: Double { get }

  func describe() -> String
}

struct Circle: HierShape {
  let radius: Double

  var area: Double { Double.pi * radius * radius }

  func draw() {}
}

struct Rect: HierShape {
  let width: Double
  let height: Double

  var area: Double { width * height }

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
