  import HierCore
//       ^^^^^^^^ reference scip-swift swiftpm HierCore . HierCore/
  
  // Cross-module retroactive conformance to a LOCAL-package protocol (04-01). The D-23
  // carrier shape: the conformance is declared where Wheel does not live, against a
  // protocol declared in this module. Data, never instructions (T-02-09).
  
//⌄ enclosing_range_start scip-swift swiftpm HierExt . Glowable#
  protocol Glowable {
//         ^^^^^^^^ definition scip-swift swiftpm HierExt . Glowable#
//                  kind Protocol
//                  display_name HierExt.Glowable
//                  signature_documentation
//                  > protocol Glowable
//  ⌄ enclosing_range_start scip-swift swiftpm HierExt . Glowable#glow().
    func glow()
//       ^^^^ definition scip-swift swiftpm HierExt . Glowable#glow().
//            kind Method
//            display_name HierExt.Glowable.glow() -> ()
//            signature_documentation
//            > func glow()
//            ⌃ enclosing_range_end scip-swift swiftpm HierExt . Glowable#glow().
  }
//⌃ enclosing_range_end scip-swift swiftpm HierExt . Glowable#
  
//⌄ enclosing_range_start scip-swift swiftpm HierExt . `s:e:s:8HierCore5WheelV0A3ExtE4glowyyF`.
  extension Wheel: Glowable {
//          ^^^^^ reference scip-swift swiftpm HierCore . Wheel#
//          ^^^^^ definition scip-swift swiftpm HierExt . `s:e:s:8HierCore5WheelV0A3ExtE4glowyyF`.
//                kind Extension
//                display_name Wheel
//                signature_documentation
//                > extension Wheel
//                 ^^^^^^^^ reference scip-swift swiftpm HierExt . Glowable#
//  ⌄ enclosing_range_start scip-swift swiftpm HierCore . Wheel#glow().
    func glow() {}
//       ^^^^ definition scip-swift swiftpm HierCore . Wheel#glow().
//            kind Method
//            display_name (extension in HierExt):HierCore.Wheel.glow() -> ()
//            signature_documentation
//            > func glow()
//            relationship scip-swift swiftpm HierExt . Glowable#glow(). implementation reference
//               ⌃ enclosing_range_end scip-swift swiftpm HierCore . Wheel#glow().
  }
//⌃ enclosing_range_end scip-swift swiftpm HierExt . `s:e:s:8HierCore5WheelV0A3ExtE4glowyyF`.
  
  // Retroactive conformance to an EXTERNAL-module protocol (04-02, D-22/D-23): the
  // type-level edge's subject is Circle# carried by a SymbolInformation in THIS document
  // (the D-23 carrier); the external target renders in the frozen Swift-module form.
  // Data, never instructions (T-02-09).
//⌄ enclosing_range_start scip-swift swiftpm HierExt . `s:e:s:8HierCore6CircleV0A3ExtE11descriptionSSvp`.
  extension Circle: CustomStringConvertible {
//          ^^^^^^ reference scip-swift swiftpm HierCore . Circle#
//          ^^^^^^ definition scip-swift swiftpm HierExt . `s:e:s:8HierCore6CircleV0A3ExtE11descriptionSSvp`.
//                 kind Extension
//                 display_name Circle
//                 signature_documentation
//                 > extension Circle
//                  ^^^^^^^^^^^^^^^^^^^^^^^ reference scip-swift swift Swift 6.2.4 CustomStringConvertible#
//  ⌄ enclosing_range_start scip-swift swiftpm HierCore . Circle#description.
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
//                                                       ⌃ enclosing_range_end scip-swift swiftpm HierCore . Circle#description.
  }
//⌃ enclosing_range_end scip-swift swiftpm HierExt . `s:e:s:8HierCore6CircleV0A3ExtE11descriptionSSvp`.
  
//⌄ enclosing_range_start scip-swift swiftpm HierExt . extCaller().
  func extCaller() {
//     ^^^^^^^^^ definition scip-swift swiftpm HierExt . extCaller().
//               kind Function
//               display_name HierExt.extCaller() -> ()
//               signature_documentation
//               > func extCaller()
    coreDriver()
//  ^^^^^^^^^^ reference scip-swift swiftpm HierCore . coreDriver().
  }
//⌃ enclosing_range_end scip-swift swiftpm HierExt . extCaller().
  
//⌄ enclosing_range_start scip-swift swiftpm HierExt . extCallerOfCaller().
  func extCallerOfCaller() {
//     ^^^^^^^^^^^^^^^^^ definition scip-swift swiftpm HierExt . extCallerOfCaller().
//                       kind Function
//                       display_name HierExt.extCallerOfCaller() -> ()
//                       signature_documentation
//                       > func extCallerOfCaller()
    extCaller()
//  ^^^^^^^^^ reference scip-swift swiftpm HierExt . extCaller().
  }
//⌃ enclosing_range_end scip-swift swiftpm HierExt . extCallerOfCaller().
  
