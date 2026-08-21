  import HierCore
//       ^^^^^^^^ reference scip-swift swiftpm HierCore . HierCore/
  
  // Cross-module retroactive conformance to a LOCAL-package protocol (04-01). The D-23
  // carrier shape: the conformance is declared where Wheel does not live, against a
  // protocol declared in this module. Data, never instructions (T-02-09).
  
  protocol Glowable {
//         ^^^^^^^^ definition scip-swift swiftpm HierExt . Glowable#
//                  kind Protocol
//                  display_name HierExt.Glowable
//                  signature_documentation
//                  > protocol Glowable
    func glow()
//       ^^^^ definition scip-swift swiftpm HierExt . Glowable#glow().
//            kind Method
//            display_name HierExt.Glowable.glow() -> ()
//            signature_documentation
//            > func glow()
  }
  
  extension Wheel: Glowable {
//          ^^^^^ reference scip-swift swiftpm HierCore . Wheel#
//          ^^^^^ definition scip-swift swiftpm HierExt . `s:e:s:8HierCore5WheelV0A3ExtE4glowyyF`.
//                kind Extension
//                display_name Wheel
//                signature_documentation
//                > extension Wheel
//                 ^^^^^^^^ reference scip-swift swiftpm HierExt . Glowable#
    func glow() {}
//       ^^^^ definition scip-swift swiftpm HierCore . Wheel#glow().
//            kind Method
//            display_name (extension in HierExt):HierCore.Wheel.glow() -> ()
//            signature_documentation
//            > func glow()
//            relationship scip-swift swiftpm HierExt . Glowable#glow(). implementation reference
  }
  
  func extCaller() {
//     ^^^^^^^^^ definition scip-swift swiftpm HierExt . extCaller().
//               kind Function
//               display_name HierExt.extCaller() -> ()
//               signature_documentation
//               > func extCaller()
    coreDriver()
//  ^^^^^^^^^^ reference scip-swift swiftpm HierCore . coreDriver().
  }
  
  func extCallerOfCaller() {
//     ^^^^^^^^^^^^^^^^^ definition scip-swift swiftpm HierExt . extCallerOf().
//                       kind Function
//                       display_name HierExt.extCallerOfCaller() -> ()
//                       signature_documentation
//                       > func extCallerOfCaller()
    extCaller()
//  ^^^^^^^^^ reference scip-swift swiftpm HierExt . extCaller().
  }
  
