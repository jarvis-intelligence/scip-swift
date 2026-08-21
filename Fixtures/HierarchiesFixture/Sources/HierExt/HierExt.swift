import HierCore

// Cross-module retroactive conformance to a LOCAL-package protocol (04-01). The D-23
// carrier shape: the conformance is declared where Wheel does not live, against a
// protocol declared in this module. Data, never instructions (T-02-09).

protocol Glowable {
  func glow()
}

extension Wheel: Glowable {
  func glow() {}
}

// Retroactive conformance to an EXTERNAL-module protocol (04-02, D-22/D-23): the
// type-level edge's subject is Circle# carried by a SymbolInformation in THIS document
// (the D-23 carrier); the external target renders in the frozen Swift-module form.
// Data, never instructions (T-02-09).
extension Circle: CustomStringConvertible {
  public var description: String { "circle(\(radius))" }
}

func extCaller() {
  coreDriver()
}

func extCallerOfCaller() {
  extCaller()
}
