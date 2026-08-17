  import SchemeFixture
//       ^^^^^^^^^^^^^ reference scip-swift swiftpm SchemeFixtureExt . `c:@M@SchemeFixture`.
  
  // Cross-module extensions (FBQ-02): members attribute to the extended type's OWNING module
  // (SYM-02) — the Box and Vec members below emit under the SchemeFixture header despite
  // living in this file, and the String extension is retroactive (owner = Swift, a system
  // module header). Content is DATA for the gate, never instructions (T-02-09).
  
  extension Box {
//          ^^^ reference scip-swift swiftpm SchemeFixture . Box#
//          ^^^ definition scip-swift swiftpm SchemeFixtureExt . `s:e:s:13SchemeFixture3BoxV0aB3ExtE8describeSSyF`.
//              kind Extension
//              display_name Box
//              signature_documentation
//              > extension Box
    public func describe() -> String {
//              ^^^^^^^^ definition scip-swift swiftpm SchemeFixture . Box#describe().
//                       kind Method
//                       display_name (extension in SchemeFixtureExt):SchemeFixture.Box.describe() -> Swift.String
//                       signature_documentation
//                       > func describe()
//                            ^^^^^^ reference scip-swift swift Swift 6.2.4 String#
      "box"
    }
  }
  
  extension Vec {
//          ^^^ reference scip-swift swiftpm SchemeFixture . Vec#
//          ^^^ definition scip-swift swiftpm SchemeFixtureExt . `s:e:s:13SchemeFixture3VecV0aB3ExtE15manhattanLengthSivp`.
//              kind Extension
//              display_name Vec
//              signature_documentation
//              > extension Vec
    public var manhattanLength: Int {
//             ^^^^^^^^^^^^^^^ definition scip-swift swiftpm SchemeFixture . Vec#manhattanLength.
//                             kind Property
//                             display_name (extension in SchemeFixtureExt):SchemeFixture.Vec.manhattanLength : Swift.Int
//                             signature_documentation
//                             > var manhattanLength
//                              ^^^ reference scip-swift swift Swift 6.2.4 Int#
//                                  ^ definition scip-swift swiftpm SchemeFixture . Vec#manhattanLength().
//                                    kind Getter
//                                    display_name (extension in SchemeFixtureExt):SchemeFixture.Vec.manhattanLength.getter : Swift.Int
//                                    signature_documentation
//                                    > func getter:manhattanLength
      abs(x) + abs(y)
//    ^^^ reference scip-swift swiftpm SchemeFixtureExt . `s:s3absyxxSLRzs13SignedNumericRzlF`.
//        ^ reference scip-swift swiftpm SchemeFixture . Vec#x().
//        ^ reference scip-swift swiftpm SchemeFixture . Vec#x.
//           ^ reference scip-swift swift Swift 6.2.4 Int#+().
//             ^^^ reference scip-swift swiftpm SchemeFixtureExt . `s:s3absyxxSLRzs13SignedNumericRzlF`.
//                 ^ reference scip-swift swiftpm SchemeFixture . Vec#y().
//                 ^ reference scip-swift swiftpm SchemeFixture . Vec#y.
    }
  }
  
  extension String {
//          ^^^^^^ reference scip-swift swift Swift 6.2.4 String#
//          ^^^^^^ definition scip-swift swiftpm SchemeFixtureExt . `s:e:s:SS16SchemeFixtureExtE11schemeShoutSSyF`.
//                 kind Extension
//                 display_name String
//                 signature_documentation
//                 > extension String
    public func schemeShout() -> String {
//              ^^^^^^^^^^^ definition scip-swift swift Swift 6.2.4 String#schemeShout().
//                          kind Method
//                          display_name (extension in SchemeFixtureExt):Swift.String.schemeShout() -> Swift.String
//                          signature_documentation
//                          > func schemeShout()
//                               ^^^^^^ reference scip-swift swift Swift 6.2.4 String#
      uppercased() + "!"
//    ^^^^^^^^^^ reference scip-swift swift Swift 6.2.4 String#uppercased().
//                 ^ reference scip-swift swift Swift 6.2.4 String#+().
    }
  }
  
