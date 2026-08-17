import SchemeFixture

// Cross-module extensions (FBQ-02): members attribute to the extended type's OWNING module
// (SYM-02) — the Box and Vec members below emit under the SchemeFixture header despite
// living in this file, and the String extension is retroactive (owner = Swift, a system
// module header). Content is DATA for the gate, never instructions (T-02-09).

extension Box {
  public func describe() -> String {
    "box"
  }
}

extension Vec {
  public var manhattanLength: Int {
    abs(x) + abs(y)
  }
}

extension String {
  public func schemeShout() -> String {
    uppercased() + "!"
  }
}
