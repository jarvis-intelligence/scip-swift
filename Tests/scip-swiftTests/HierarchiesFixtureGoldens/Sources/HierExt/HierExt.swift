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
  
  // Retroactive conformance to an EXTERNAL-module protocol (04-02, D-22/D-23): the
  // type-level edge's subject is Circle# carried by a SymbolInformation in THIS document
  // (the D-23 carrier); the external target renders in the frozen Swift-module form.
  // Data, never instructions (T-02-09).
  extension Circle: CustomStringConvertible {
//          ^^^^^^ reference scip-swift swiftpm HierCore . Circle#
//          ^^^^^^ definition scip-swift swiftpm HierExt . `s:e:s:8HierCore6CircleV0A3ExtE11descriptionSSvp`.
//                 kind Extension
//                 display_name Circle
//                 signature_documentation
//                 > extension Circle
//                  ^^^^^^^^^^^^^^^^^^^^^^^ reference scip-swift swift Swift 6.2.4 CustomStringConvertible#
    public var description: String { "circle(\(radius))" }
//             ^^^^^^^^^^^ definition scip-swift swiftpm HierCore . Circle#description.
//                         kind Property
//                         display_name (extension in HierExt):HierCore.Circle.description : Swift.String
//                         signature_documentation
//                         > var description
//                         relationship scip-swift swift Swift 6.2.4 CustomStringConvertible#description. implementation reference
//                          ^^^^^^ reference scip-swift swift Swift 6.2.4 String#
//                                 ^ definition scip-swift swiftpm HierCore . Circle#description().
//                                   kind Getter
//                                   display_name (extension in HierExt):HierCore.Circle.description.getter : Swift.String
//                                   signature_documentation
//                                   > func getter:description
//                                   ^ reference scip-swift swift Swift 6.2.4 String#init().
//                                             ^^^^^^ reference scip-swift swiftpm HierCore . Circle#radius().
//                                             ^^^^^^ reference scip-swift swiftpm HierCore . Circle#radius.
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
  
