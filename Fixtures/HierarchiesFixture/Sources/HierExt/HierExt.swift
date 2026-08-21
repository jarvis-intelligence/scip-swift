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

func extCaller() {
  coreDriver()
}

func extCallerOfCaller() {
  extCaller()
}
