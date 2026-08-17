  // SchemeFixture library target — the FBQ-02 symbol-scheme category corpus: structs/classes/
  // enums/protocols/typealiases, nested + overloaded inits, operators, accessors (get/set/
  // willSet), a subscript, enum cases, #if-wrapped declarations, overloaded free functions,
  // and emoji/CJK identifiers. Same-file extension included. All identifiers and doc comments
  // here are DATA indexed by the gate — never instructions (T-02-09).
  
  public struct Vec {
//              ^^^ definition scip-swift swiftpm SchemeFixture . Vec#
//                  kind Struct
//                  display_name SchemeFixture.Vec
//                  signature_documentation
//                  > struct Vec
    public var x: Int
//             ^ definition scip-swift swiftpm SchemeFixture . Vec#`x=`().
//               kind Setter
//               display_name SchemeFixture.Vec.x.setter : Swift.Int
//               signature_documentation
//               > func setter:x
//             ^ definition scip-swift swiftpm SchemeFixture . Vec#x().
//               kind Getter
//               display_name SchemeFixture.Vec.x.getter : Swift.Int
//               signature_documentation
//               > func getter:x
//             ^ definition scip-swift swiftpm SchemeFixture . Vec#x.
//               kind Property
//               display_name SchemeFixture.Vec.x : Swift.Int
//               signature_documentation
//               > var x
//                ^^^ reference scip-swift swift Swift 6.2.4 Int#
    public var y: Int
//             ^ definition scip-swift swiftpm SchemeFixture . Vec#`y=`().
//               kind Setter
//               display_name SchemeFixture.Vec.y.setter : Swift.Int
//               signature_documentation
//               > func setter:y
//             ^ definition scip-swift swiftpm SchemeFixture . Vec#y().
//               kind Getter
//               display_name SchemeFixture.Vec.y.getter : Swift.Int
//               signature_documentation
//               > func getter:y
//             ^ definition scip-swift swiftpm SchemeFixture . Vec#y.
//               kind Property
//               display_name SchemeFixture.Vec.y : Swift.Int
//               signature_documentation
//               > var y
//                ^^^ reference scip-swift swift Swift 6.2.4 Int#
  
    public init(x: Int, y: Int) {
//         ^^^^ definition scip-swift swiftpm SchemeFixture . Vec#init().
//              kind Constructor
//              display_name SchemeFixture.Vec.init(x: Swift.Int, y: Swift.Int) -> SchemeFixture.Vec
//              signature_documentation
//              > init init(x:y:)
//              ^ definition scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecV1x1yACSi_SitcfcADL_Sivp`.
//                kind Parameter
//                display_name x #1 : Swift.Int in SchemeFixture.Vec.init(x: Swift.Int, y: Swift.Int) -> SchemeFixture.Vec
//                 ^^^ reference scip-swift swift Swift 6.2.4 Int#
//                      ^ definition scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecV1x1yACSi_SitcfcAEL_Sivp`.
//                        kind Parameter
//                        display_name y #1 : Swift.Int in SchemeFixture.Vec.init(x: Swift.Int, y: Swift.Int) -> SchemeFixture.Vec
//                         ^^^ reference scip-swift swift Swift 6.2.4 Int#
      self.x = x
//         ^ reference scip-swift swiftpm SchemeFixture . Vec#`x=`().
//         ^ reference scip-swift swiftpm SchemeFixture . Vec#x.
//             ^ reference scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecV1x1yACSi_SitcfcADL_Sivp`.
      self.y = y
//         ^ reference scip-swift swiftpm SchemeFixture . Vec#`y=`().
//         ^ reference scip-swift swiftpm SchemeFixture . Vec#y.
//             ^ reference scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecV1x1yACSi_SitcfcAEL_Sivp`.
    }
  
    public init(scalar: Int) {
//         ^^^^ definition scip-swift swiftpm SchemeFixture . Vec#init(+1).
//              kind Constructor
//              display_name SchemeFixture.Vec.init(scalar: Swift.Int) -> SchemeFixture.Vec
//              signature_documentation
//              > init init(scalar:)
//              ^^^^^^ definition scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecV6scalarACSi_tcfcADL_Sivp`.
//                     kind Parameter
//                     display_name scalar #1 : Swift.Int in SchemeFixture.Vec.init(scalar: Swift.Int) -> SchemeFixture.Vec
//                      ^^^ reference scip-swift swift Swift 6.2.4 Int#
      self.init(x: scalar, y: scalar)
//         ^^^^ reference scip-swift swiftpm SchemeFixture . Vec#init().
//                 ^^^^^^ reference scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecV6scalarACSi_tcfcADL_Sivp`.
//                            ^^^^^^ reference scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecV6scalarACSi_tcfcADL_Sivp`.
    }
  
    public static func == (lhs: Vec, rhs: Vec) -> Bool {
//                     ^^ definition scip-swift swiftpm SchemeFixture . Vec#`==`().
//                        kind StaticMethod
//                        display_name static SchemeFixture.Vec.== infix(SchemeFixture.Vec, SchemeFixture.Vec) -> Swift.Bool
//                        signature_documentation
//                        > static func ==(_:_:)
//                         ^^^ definition scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecV2eeoiySbAC_ACtFZ3lhsL_ACvp`.
//                             kind Parameter
//                             display_name lhs #1 : SchemeFixture.Vec in static SchemeFixture.Vec.== infix(SchemeFixture.Vec, SchemeFixture.Vec) -> Swift.Bool
//                              ^^^ reference scip-swift swiftpm SchemeFixture . Vec#
//                                   ^^^ definition scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecV2eeoiySbAC_ACtFZ3rhsL_ACvp`.
//                                       kind Parameter
//                                       display_name rhs #1 : SchemeFixture.Vec in static SchemeFixture.Vec.== infix(SchemeFixture.Vec, SchemeFixture.Vec) -> Swift.Bool
//                                        ^^^ reference scip-swift swiftpm SchemeFixture . Vec#
//                                                ^^^^ reference scip-swift swift Swift 6.2.4 Bool#
      lhs.x == rhs.x && lhs.y == rhs.y
//    ^^^ reference scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecV2eeoiySbAC_ACtFZ3lhsL_ACvp`.
//        ^ reference scip-swift swiftpm SchemeFixture . Vec#x().
//        ^ reference scip-swift swiftpm SchemeFixture . Vec#x.
//          ^^ reference scip-swift swift Swift 6.2.4 Int#`==`().
//             ^^^ reference scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecV2eeoiySbAC_ACtFZ3rhsL_ACvp`.
//                 ^ reference scip-swift swiftpm SchemeFixture . Vec#x().
//                 ^ reference scip-swift swiftpm SchemeFixture . Vec#x.
//                   ^^ reference scip-swift swift Swift 6.2.4 Bool#`&&`().
//                      ^^^ reference scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecV2eeoiySbAC_ACtFZ3lhsL_ACvp`.
//                          ^ reference scip-swift swiftpm SchemeFixture . Vec#y().
//                          ^ reference scip-swift swiftpm SchemeFixture . Vec#y.
//                            ^^ reference scip-swift swift Swift 6.2.4 Int#`==`().
//                               ^^^ reference scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecV2eeoiySbAC_ACtFZ3rhsL_ACvp`.
//                                   ^ reference scip-swift swiftpm SchemeFixture . Vec#y().
//                                   ^ reference scip-swift swiftpm SchemeFixture . Vec#y.
    }
  
    public static func + (lhs: Vec, rhs: Vec) -> Vec {
//                     ^ definition scip-swift swiftpm SchemeFixture . Vec#+().
//                       kind StaticMethod
//                       display_name static SchemeFixture.Vec.+ infix(SchemeFixture.Vec, SchemeFixture.Vec) -> SchemeFixture.Vec
//                       signature_documentation
//                       > static func +(_:_:)
//                        ^^^ definition scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecV1poiyA2C_ACtFZ3lhsL_ACvp`.
//                            kind Parameter
//                            display_name lhs #1 : SchemeFixture.Vec in static SchemeFixture.Vec.+ infix(SchemeFixture.Vec, SchemeFixture.Vec) -> SchemeFixture.Vec
//                             ^^^ reference scip-swift swiftpm SchemeFixture . Vec#
//                                  ^^^ definition scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecV1poiyA2C_ACtFZ3rhsL_ACvp`.
//                                      kind Parameter
//                                      display_name rhs #1 : SchemeFixture.Vec in static SchemeFixture.Vec.+ infix(SchemeFixture.Vec, SchemeFixture.Vec) -> SchemeFixture.Vec
//                                       ^^^ reference scip-swift swiftpm SchemeFixture . Vec#
//                                               ^^^ reference scip-swift swiftpm SchemeFixture . Vec#
      Vec(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
//    ^^^ reference scip-swift swiftpm SchemeFixture . Vec#
//    ^^^ reference scip-swift swiftpm SchemeFixture . Vec#init().
//           ^^^ reference scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecV1poiyA2C_ACtFZ3lhsL_ACvp`.
//               ^ reference scip-swift swiftpm SchemeFixture . Vec#x().
//               ^ reference scip-swift swiftpm SchemeFixture . Vec#x.
//                 ^ reference scip-swift swift Swift 6.2.4 Int#+().
//                   ^^^ reference scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecV1poiyA2C_ACtFZ3rhsL_ACvp`.
//                       ^ reference scip-swift swiftpm SchemeFixture . Vec#x().
//                       ^ reference scip-swift swiftpm SchemeFixture . Vec#x.
//                             ^^^ reference scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecV1poiyA2C_ACtFZ3lhsL_ACvp`.
//                                 ^ reference scip-swift swiftpm SchemeFixture . Vec#y().
//                                 ^ reference scip-swift swiftpm SchemeFixture . Vec#y.
//                                   ^ reference scip-swift swift Swift 6.2.4 Int#+().
//                                     ^^^ reference scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecV1poiyA2C_ACtFZ3rhsL_ACvp`.
//                                         ^ reference scip-swift swiftpm SchemeFixture . Vec#y().
//                                         ^ reference scip-swift swiftpm SchemeFixture . Vec#y.
    }
  
    public subscript(index: Int) -> Int {
//         ^^^^^^^^^ definition scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecVyS2icip`.
//                   kind Subscript
//                   display_name SchemeFixture.Vec.subscript(Swift.Int) -> Swift.Int
//                   signature_documentation
//                   > var subscript(_:)
//                   ^^^^^ definition scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecVyS2icip5indexL_Sivp`.
//                         kind Parameter
//                         display_name index #1 : Swift.Int in SchemeFixture.Vec.subscript(Swift.Int) -> Swift.Int
//                          ^^^ reference scip-swift swift Swift 6.2.4 Int#
//                                  ^^^ reference scip-swift swift Swift 6.2.4 Int#
//                                      ^ definition scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3VecVyS2icig`.
//                                        kind Getter
//                                        display_name SchemeFixture.Vec.subscript.getter : (Swift.Int) -> Swift.Int
//                                        signature_documentation
//                                        > func getter:subscript(_:)
      index == 0 ? x : y
//          ^^ reference scip-swift swift Swift 6.2.4 Int#`==`().
//                 ^ reference scip-swift swiftpm SchemeFixture . Vec#x().
//                 ^ reference scip-swift swiftpm SchemeFixture . Vec#x.
//                     ^ reference scip-swift swiftpm SchemeFixture . Vec#y().
//                     ^ reference scip-swift swiftpm SchemeFixture . Vec#y.
    }
  }
  
  public struct Box<T> {
//              ^^^ definition scip-swift swiftpm SchemeFixture . Box#
//                  kind Struct
//                  display_name SchemeFixture.Box
//                  signature_documentation
//                  > struct Box
//                  ^ definition scip-swift swiftpm SchemeFixture . Box#T#
//                    kind TypeAlias
//                    display_name SchemeFixture.Box.T
//                    signature_documentation
//                    > typealias T
    public var content: T
//             ^^^^^^^ definition scip-swift swiftpm SchemeFixture . Box#`content=`().
//                     kind Setter
//                     display_name SchemeFixture.Box.content.setter : A
//                     signature_documentation
//                     > func setter:content
//             ^^^^^^^ definition scip-swift swiftpm SchemeFixture . Box#content().
//                     kind Getter
//                     display_name SchemeFixture.Box.content.getter : A
//                     signature_documentation
//                     > func getter:content
//             ^^^^^^^ definition scip-swift swiftpm SchemeFixture . Box#content.
//                     kind Property
//                     display_name SchemeFixture.Box.content : A
//                     signature_documentation
//                     > var content
//                      ^ reference scip-swift swiftpm SchemeFixture . Box#T#
  
    public init(content: T) {
//         ^^^^ definition scip-swift swiftpm SchemeFixture . Box#init().
//              kind Constructor
//              display_name SchemeFixture.Box.init(content: A) -> SchemeFixture.Box<A>
//              signature_documentation
//              > init init(content:)
//              ^^^^^^^ definition scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3BoxV7contentACyxGx_tcfcADL_xvp`.
//                      kind Parameter
//                      display_name content #1 : A in SchemeFixture.Box.init(content: A) -> SchemeFixture.Box<A>
//                       ^ reference scip-swift swiftpm SchemeFixture . Box#T#
      self.content = content
//         ^^^^^^^ reference scip-swift swiftpm SchemeFixture . Box#`content=`().
//         ^^^^^^^ reference scip-swift swiftpm SchemeFixture . Box#content.
//                   ^^^^^^^ reference scip-swift swiftpm SchemeFixture . `s:13SchemeFixture3BoxV7contentACyxGx_tcfcADL_xvp`.
    }
  
    public func unwrap() -> T {
//              ^^^^^^ definition scip-swift swiftpm SchemeFixture . Box#unwrap().
//                     kind Method
//                     display_name SchemeFixture.Box.unwrap() -> A
//                     signature_documentation
//                     > func unwrap()
//                          ^ reference scip-swift swiftpm SchemeFixture . Box#T#
      content
//    ^^^^^^^ reference scip-swift swiftpm SchemeFixture . Box#content().
//    ^^^^^^^ reference scip-swift swiftpm SchemeFixture . Box#content.
    }
  }
  
  public protocol Drawable {
//                ^^^^^^^^ definition scip-swift swiftpm SchemeFixture . Drawable#
//                         kind Protocol
//                         display_name SchemeFixture.Drawable
//                         signature_documentation
//                         > protocol Drawable
    func draw() -> String
//       ^^^^ definition scip-swift swiftpm SchemeFixture . Drawable#draw().
//            kind Method
//            display_name SchemeFixture.Drawable.draw() -> Swift.String
//            signature_documentation
//            > func draw()
//                 ^^^^^^ reference scip-swift swift Swift 6.2.4 String#
  }
  
  public final class Poster: Drawable {
//                   ^^^^^^ definition scip-swift swiftpm SchemeFixture . Poster#
//                          kind Class
//                          display_name SchemeFixture.Poster
//                          signature_documentation
//                          > class Poster
//                           ^^^^^^^^ reference scip-swift swiftpm SchemeFixture . Drawable#
    public var label: String = ""
//             ^^^^^ definition scip-swift swiftpm SchemeFixture . Poster#`label=`().
//                   kind Setter
//                   display_name SchemeFixture.Poster.label.setter : Swift.String
//                   signature_documentation
//                   > func setter:label
//             ^^^^^ definition scip-swift swiftpm SchemeFixture . Poster#label().
//                   kind Getter
//                   display_name SchemeFixture.Poster.label.getter : Swift.String
//                   signature_documentation
//                   > func getter:label
//             ^^^^^ definition scip-swift swiftpm SchemeFixture . Poster#label.
//                   kind Property
//                   display_name SchemeFixture.Poster.label : Swift.String
//                   signature_documentation
//                   > var label
//                    ^^^^^^ reference scip-swift swift Swift 6.2.4 String#
  
    public init() {}
//         ^^^^ definition scip-swift swiftpm SchemeFixture . Poster#init().
//              kind Constructor
//              display_name SchemeFixture.Poster.init() -> SchemeFixture.Poster
//              signature_documentation
//              > init init()
  
    public func draw() -> String {
//              ^^^^ definition scip-swift swiftpm SchemeFixture . Poster#draw().
//                   kind Method
//                   display_name SchemeFixture.Poster.draw() -> Swift.String
//                   signature_documentation
//                   > func draw()
//                   relationship scip-swift swiftpm SchemeFixture . Drawable#draw(). implementation reference
//                        ^^^^^^ reference scip-swift swift Swift 6.2.4 String#
      "poster(\(label))"
//    ^ reference scip-swift swift Swift 6.2.4 String#init().
//              ^^^^^ reference scip-swift swiftpm SchemeFixture . Poster#label().
//              ^^^^^ reference scip-swift swiftpm SchemeFixture . Poster#label.
    }
  }
  
  public final class Observed {
//                   ^^^^^^^^ definition scip-swift swiftpm SchemeFixture . Observed#
//                            kind Class
//                            display_name SchemeFixture.Observed
//                            signature_documentation
//                            > class Observed
    public var computed: Int {
//             ^^^^^^^^ definition scip-swift swiftpm SchemeFixture . Observed#computed.
//                      kind Property
//                      display_name SchemeFixture.Observed.computed : Swift.Int
//                      signature_documentation
//                      > var computed
//                       ^^^ reference scip-swift swift Swift 6.2.4 Int#
      get { backing }
//    ^^^ definition scip-swift swiftpm SchemeFixture . Observed#computed().
//        kind Getter
//        display_name SchemeFixture.Observed.computed.getter : Swift.Int
//        signature_documentation
//        > func getter:computed
//          ^^^^^^^ reference scip-swift swiftpm SchemeFixture . Observed#backing().
//          ^^^^^^^ reference scip-swift swiftpm SchemeFixture . Observed#backing.
      set { backing = newValue }
//    ^^^ definition scip-swift swiftpm SchemeFixture . Observed#`computed=`().
//        kind Setter
//        display_name SchemeFixture.Observed.computed.setter : Swift.Int
//        signature_documentation
//        > func setter:computed
//          ^^^^^^^ reference scip-swift swiftpm SchemeFixture . Observed#`backing=`().
//          ^^^^^^^ reference scip-swift swiftpm SchemeFixture . Observed#backing.
    }
  
    private var backing: Int = 0
//              ^^^^^^^ definition scip-swift swiftpm SchemeFixture . Observed#`backing=`().
//                      kind Setter
//                      display_name SchemeFixture.Observed.(backing in _52B7EAE41E39CB1B4EE381C49B54B7C4).setter : Swift.Int
//                      signature_documentation
//                      > func setter:backing
//              ^^^^^^^ definition scip-swift swiftpm SchemeFixture . Observed#backing().
//                      kind Getter
//                      display_name SchemeFixture.Observed.(backing in _52B7EAE41E39CB1B4EE381C49B54B7C4).getter : Swift.Int
//                      signature_documentation
//                      > func getter:backing
//              ^^^^^^^ definition scip-swift swiftpm SchemeFixture . Observed#backing.
//                      kind Property
//                      display_name SchemeFixture.Observed.(backing in _52B7EAE41E39CB1B4EE381C49B54B7C4) : Swift.Int
//                      signature_documentation
//                      > var backing
//                       ^^^ reference scip-swift swift Swift 6.2.4 Int#
  
    public var watched: Int = 0 {
//             ^^^^^^^ definition scip-swift swiftpm SchemeFixture . Observed#`watched=`().
//                     kind Setter
//                     display_name SchemeFixture.Observed.watched.setter : Swift.Int
//                     signature_documentation
//                     > func setter:watched
//             ^^^^^^^ definition scip-swift swiftpm SchemeFixture . Observed#watched().
//                     kind Getter
//                     display_name SchemeFixture.Observed.watched.getter : Swift.Int
//                     signature_documentation
//                     > func getter:watched
//             ^^^^^^^ definition scip-swift swiftpm SchemeFixture . Observed#watched.
//                     kind Property
//                     display_name SchemeFixture.Observed.watched : Swift.Int
//                     signature_documentation
//                     > var watched
//                      ^^^ reference scip-swift swift Swift 6.2.4 Int#
      willSet {
//    ^^^^^^^ definition scip-swift swiftpm SchemeFixture . Observed#`watched=`(+1).
//            kind Setter
//            display_name SchemeFixture.Observed.watched.willset : Swift.Int
//            signature_documentation
//            > func willSet:watched
        prepared = true
//      ^^^^^^^^ reference scip-swift swiftpm SchemeFixture . Observed#`prepared=`().
//      ^^^^^^^^ reference scip-swift swiftpm SchemeFixture . Observed#prepared.
      }
    }
  
    public var prepared = false
//             ^^^^^^^^ definition scip-swift swiftpm SchemeFixture . Observed#`prepared=`().
//                      kind Setter
//                      display_name SchemeFixture.Observed.prepared.setter : Swift.Bool
//                      signature_documentation
//                      > func setter:prepared
//             ^^^^^^^^ definition scip-swift swiftpm SchemeFixture . Observed#prepared().
//                      kind Getter
//                      display_name SchemeFixture.Observed.prepared.getter : Swift.Bool
//                      signature_documentation
//                      > func getter:prepared
//             ^^^^^^^^ definition scip-swift swiftpm SchemeFixture . Observed#prepared.
//                      kind Property
//                      display_name SchemeFixture.Observed.prepared : Swift.Bool
//                      signature_documentation
//                      > var prepared
  
    public init() {}
//         ^^^^ definition scip-swift swiftpm SchemeFixture . Observed#init().
//              kind Constructor
//              display_name SchemeFixture.Observed.init() -> SchemeFixture.Observed
//              signature_documentation
//              > init init()
  }
  
  public enum Spectrum {
//            ^^^^^^^^ definition scip-swift swiftpm SchemeFixture . Spectrum#
//                     kind Enum
//                     display_name SchemeFixture.Spectrum
//                     signature_documentation
//                     > enum Spectrum
    case red
//       ^^^ definition scip-swift swiftpm SchemeFixture . Spectrum#red.
//           kind EnumMember
//           display_name SchemeFixture.Spectrum.red(SchemeFixture.Spectrum.Type) -> SchemeFixture.Spectrum
    case green
//       ^^^^^ definition scip-swift swiftpm SchemeFixture . Spectrum#green.
//             kind EnumMember
//             display_name SchemeFixture.Spectrum.green(SchemeFixture.Spectrum.Type) -> SchemeFixture.Spectrum
    case blue
//       ^^^^ definition scip-swift swiftpm SchemeFixture . Spectrum#blue.
//            kind EnumMember
//            display_name SchemeFixture.Spectrum.blue(SchemeFixture.Spectrum.Type) -> SchemeFixture.Spectrum
  }
  
  public typealias Point = Vec
//                 ^^^^^ definition scip-swift swiftpm SchemeFixture . Point#
//                       kind TypeAlias
//                       display_name SchemeFixture.Point
//                       signature_documentation
//                       > typealias Point
//                         ^^^ reference scip-swift swiftpm SchemeFixture . Vec#
  
  public func parse(_ text: String) -> Int {
//            ^^^^^ definition scip-swift swiftpm SchemeFixture . parse().
//                  kind Function
//                  display_name SchemeFixture.parse(Swift.String) -> Swift.Int
//                  signature_documentation
//                  > func parse(_:)
//                    ^^^^ definition local text
//                         kind Parameter
//                         display_name text
//                         enclosing_symbol scip-swift swiftpm SchemeFixture . parse().
//                          ^^^^^^ reference scip-swift swift Swift 6.2.4 String#
//                                     ^^^ reference scip-swift swift Swift 6.2.4 Int#
    Int(text) ?? 0
//  ^^^ reference scip-swift swift Swift 6.2.4 Int#
//  ^^^ reference scip-swift swiftpm SchemeFixture . `s:s17FixedWidthIntegerPsEyxSgSScfc`.
//            ^^ reference scip-swift swiftpm SchemeFixture . `s:s2qqoiyxxSgn_xyKXKtKRi_zlF`.
  }
  
  public func parse(_ value: Int) -> String {
//            ^^^^^ definition scip-swift swiftpm SchemeFixture . parse(+1).
//                  kind Function
//                  display_name SchemeFixture.parse(Swift.Int) -> Swift.String
//                  signature_documentation
//                  > func parse(_:)
//                    ^^^^^ definition local value_1
//                          kind Parameter
//                          display_name value
//                          enclosing_symbol scip-swift swiftpm SchemeFixture . parse().
//                           ^^^ reference scip-swift swift Swift 6.2.4 Int#
//                                   ^^^^^^ reference scip-swift swift Swift 6.2.4 String#
    String(value)
//  ^^^^^^ reference scip-swift swift Swift 6.2.4 String#
//  ^^^^^^ reference scip-swift swiftpm SchemeFixture . `s:SSySSxcs25LosslessStringConvertibleRzlufc`.
  }
  
  extension Vec {
//          ^^^ reference scip-swift swiftpm SchemeFixture . Vec#
//          ^^^ definition scip-swift swiftpm SchemeFixture . `s:e:s:13SchemeFixture3VecV6lengthSdyF`.
//              kind Extension
//              display_name Vec
//              signature_documentation
//              > extension Vec
    public func length() -> Double {
//              ^^^^^^ definition scip-swift swiftpm SchemeFixture . Vec#length().
//                     kind Method
//                     display_name SchemeFixture.Vec.length() -> Swift.Double
//                     signature_documentation
//                     > func length()
//                          ^^^^^^ reference scip-swift swift Swift 6.2.4 Double#
      Double(x * x + y * y)
//    ^^^^^^ reference scip-swift swift Swift 6.2.4 Double#
//    ^^^^^^ reference scip-swift swiftpm SchemeFixture . `s:SdySdSicfc`.
//           ^ reference scip-swift swiftpm SchemeFixture . Vec#x().
//           ^ reference scip-swift swiftpm SchemeFixture . Vec#x.
//             ^ reference scip-swift swift Swift 6.2.4 Int#`*`().
//               ^ reference scip-swift swiftpm SchemeFixture . Vec#x().
//               ^ reference scip-swift swiftpm SchemeFixture . Vec#x.
//                 ^ reference scip-swift swift Swift 6.2.4 Int#+().
//                   ^ reference scip-swift swiftpm SchemeFixture . Vec#y().
//                   ^ reference scip-swift swiftpm SchemeFixture . Vec#y.
//                     ^ reference scip-swift swift Swift 6.2.4 Int#`*`().
//                       ^ reference scip-swift swiftpm SchemeFixture . Vec#y().
//                       ^ reference scip-swift swiftpm SchemeFixture . Vec#y.
    }
  }
  
  public let 🚀 = "rocket"
//           ^^^^ definition scip-swift swiftpm SchemeFixture . `🚀=`().
//                kind Setter
//                display_name SchemeFixture.🚀.setter : Swift.String
//                signature_documentation
//                > func setter:🚀
//           ^^^^ definition scip-swift swiftpm SchemeFixture . `🚀`().
//                kind Getter
//                display_name SchemeFixture.🚀.getter : Swift.String
//                signature_documentation
//                > func getter:🚀
//           ^^^^ definition scip-swift swiftpm SchemeFixture . `🚀`.
//                kind Variable
//                display_name SchemeFixture.🚀 : Swift.String
//                signature_documentation
//                > var 🚀
  public let π = 3.14159
//           ^^ definition scip-swift swiftpm SchemeFixture . `π=`().
//              kind Setter
//              display_name SchemeFixture.π.setter : Swift.Double
//              signature_documentation
//              > func setter:π
//           ^^ definition scip-swift swiftpm SchemeFixture . `π`().
//              kind Getter
//              display_name SchemeFixture.π.getter : Swift.Double
//              signature_documentation
//              > func getter:π
//           ^^ definition scip-swift swiftpm SchemeFixture . `π`.
//              kind Variable
//              display_name SchemeFixture.π : Swift.Double
//              signature_documentation
//              > var π
  
  public func 名前を付ける() -> String {
//            ^^^^^^^^^^^^^^^^^^ definition scip-swift swiftpm SchemeFixture . `名前を付ける`().
//                               kind Function
//                               display_name SchemeFixture.名前を付ける() -> Swift.String
//                               signature_documentation
//                               > func 名前を付ける()
//                                    ^^^^^^ reference scip-swift swift Swift 6.2.4 String#
    "名前"
  }
  
  #if canImport(Darwin)
  public func conditionallyCompiled() -> Bool {
//            ^^^^^^^^^^^^^^^^^^^^^ definition scip-swift swiftpm SchemeFixture . conditionallyCompiled().
//                                  kind Function
//                                  display_name SchemeFixture.conditionallyCompiled() -> Swift.Bool
//                                  signature_documentation
//                                  > func conditionallyCompiled()
//                                       ^^^^ reference scip-swift swift Swift 6.2.4 Bool#
    true
  }
  #else
  public func conditionallyCompiledElsewhere() -> Bool {
    false
  }
  #endif
  
  public let flagSequence = "🇻🇳🇯🇵"
//           ^^^^^^^^^^^^ definition scip-swift swiftpm SchemeFixture . `flagSequence=`().
//                        kind Setter
//                        display_name SchemeFixture.flagSequence.setter : Swift.String
//                        signature_documentation
//                        > func setter:flagSequence
//           ^^^^^^^^^^^^ definition scip-swift swiftpm SchemeFixture . flagSequence().
//                        kind Getter
//                        display_name SchemeFixture.flagSequence.getter : Swift.String
//                        signature_documentation
//                        > func getter:flagSequence
//           ^^^^^^^^^^^^ definition scip-swift swiftpm SchemeFixture . flagSequence.
//                        kind Variable
//                        display_name SchemeFixture.flagSequence : Swift.String
//                        signature_documentation
//                        > var flagSequence
  
