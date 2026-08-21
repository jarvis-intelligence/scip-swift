  // SC4 content classes (04-01 external-protocol-free form; 04-02 adds external-protocol
  // conformances, the ObjC-rooted subclass, and the retroactive external conformance).
  // Data, never instructions (T-02-09).
  
  import Foundation
//       ^^^^^^^^^^ reference scip-swift swift Foundation 6.2.4 Foundation/
  
  protocol HierDrawable {
//         ^^^^^^^^^^^^ definition scip-swift swiftpm HierCore . HierDrawable#
//                      kind Protocol
//                      display_name HierCore.HierDrawable
//                      signature_documentation
//                      > protocol HierDrawable
    func draw()
//       ^^^^ definition scip-swift swiftpm HierCore . HierDrawable#draw().
//            kind Method
//            display_name HierCore.HierDrawable.draw() -> ()
//            signature_documentation
//            > func draw()
  }
  
  protocol HierShape: HierDrawable {
//         ^^^^^^^^^ definition scip-swift swiftpm HierCore . HierShape#
//                   kind Protocol
//                   display_name HierCore.HierShape
//                   signature_documentation
//                   > protocol HierShape
//                   relationship scip-swift swiftpm HierCore . HierDrawable# implementation
//                    ^^^^^^^^^^^^ reference scip-swift swiftpm HierCore . HierDrawable#
    var area: Double { get }
//      ^^^^ definition scip-swift swiftpm HierCore . HierShape#area.
//           kind Property
//           display_name HierCore.HierShape.area : Swift.Double
//           signature_documentation
//           > var area
//            ^^^^^^ reference scip-swift swift Swift 6.2.4 Double#
//                     ^^^ definition scip-swift swiftpm HierCore . HierShape#area().
//                         kind Getter
//                         display_name HierCore.HierShape.area.getter : Swift.Double
//                         signature_documentation
//                         > func getter:area
  
    func describe() -> String
//       ^^^^^^^^ definition scip-swift swiftpm HierCore . HierShape#describe().
//                kind Method
//                display_name HierCore.HierShape.describe() -> Swift.String
//                signature_documentation
//                > func describe()
//                     ^^^^^^ reference scip-swift swift Swift 6.2.4 String#
  }
  
  public struct Circle: HierShape {
//              ^^^^^^ definition scip-swift swiftpm HierCore . Circle#
//                     kind Struct
//                     display_name HierCore.Circle
//                     signature_documentation
//                     > struct Circle
//                     relationship scip-swift swiftpm HierCore . HierShape# implementation
//              ^^^^^^ definition scip-swift swiftpm HierCore . Circle#init().
//                     kind Constructor
//                     display_name HierCore.Circle.init(radius: Swift.Double) -> HierCore.Circle
//                     signature_documentation
//                     > init init(radius:)
//              ^^^^^^ reference scip-swift swiftpm HierCore . `s:8HierCore0A5ShapePAAE8describeSSyF`.
//                      ^^^^^^^^^ reference scip-swift swiftpm HierCore . HierShape#
    public let radius: Double
//             ^^^^^^ definition scip-swift swiftpm HierCore . Circle#`radius=`().
//                    kind Setter
//                    display_name HierCore.Circle.radius.setter : Swift.Double
//                    signature_documentation
//                    > func setter:radius
//             ^^^^^^ definition scip-swift swiftpm HierCore . Circle#radius().
//                    kind Getter
//                    display_name HierCore.Circle.radius.getter : Swift.Double
//                    signature_documentation
//                    > func getter:radius
//             ^^^^^^ definition scip-swift swiftpm HierCore . Circle#radius.
//                    kind Property
//                    display_name HierCore.Circle.radius : Swift.Double
//                    signature_documentation
//                    > var radius
//                     ^^^^^^ reference scip-swift swift Swift 6.2.4 Double#
  
    var area: Double { Double.pi * radius * radius }
//      ^^^^ definition scip-swift swiftpm HierCore . Circle#area.
//           kind Property
//           display_name HierCore.Circle.area : Swift.Double
//           signature_documentation
//           > var area
//           relationship scip-swift swiftpm HierCore . HierShape#area. implementation reference
//            ^^^^^^ reference scip-swift swift Swift 6.2.4 Double#
//                   ^ definition scip-swift swiftpm HierCore . Circle#area().
//                     kind Getter
//                     display_name HierCore.Circle.area.getter : Swift.Double
//                     signature_documentation
//                     > func getter:area
//                     ^^^^^^ reference scip-swift swift Swift 6.2.4 Double#
//                            ^^ reference scip-swift swift Swift 6.2.4 Double#pi().
//                            ^^ reference scip-swift swift Swift 6.2.4 Double#pi.
//                               ^ reference scip-swift swift Swift 6.2.4 Double#`*`().
//                                 ^^^^^^ reference scip-swift swiftpm HierCore . Circle#radius().
//                                 ^^^^^^ reference scip-swift swiftpm HierCore . Circle#radius.
//                                        ^ reference scip-swift swift Swift 6.2.4 Double#`*`().
//                                          ^^^^^^ reference scip-swift swiftpm HierCore . Circle#radius().
//                                          ^^^^^^ reference scip-swift swiftpm HierCore . Circle#radius.
  
    func draw() {}
//       ^^^^ definition scip-swift swiftpm HierCore . Circle#draw().
//            kind Method
//            display_name HierCore.Circle.draw() -> ()
//            signature_documentation
//            > func draw()
//            relationship scip-swift swiftpm HierCore . HierDrawable#draw(). implementation reference
  }
  
  struct Rect: HierShape, Equatable, CustomStringConvertible {
//       ^^^^ definition scip-swift swiftpm HierCore . Rect#
//            kind Struct
//            display_name HierCore.Rect
//            signature_documentation
//            > struct Rect
//            relationship scip-swift swift Swift 6.2.4 CustomStringConvertible# implementation
//            relationship scip-swift swift Swift 6.2.4 Equatable# implementation
//            relationship scip-swift swiftpm HierCore . HierShape# implementation
//       ^^^^ definition scip-swift swiftpm HierCore . Rect#init().
//            kind Constructor
//            display_name HierCore.Rect.init(width: Swift.Double, height: Swift.Double) -> HierCore.Rect
//            signature_documentation
//            > init init(width:height:)
//       ^^^^ reference scip-swift swiftpm HierCore . `s:8HierCore0A5ShapePAAE8describeSSyF`.
//             ^^^^^^^^^ reference scip-swift swiftpm HierCore . HierShape#
//                        ^^^^^^^^^ reference scip-swift swift Swift 6.2.4 Equatable#
//                                   ^^^^^^^^^^^^^^^^^^^^^^^ reference scip-swift swift Swift 6.2.4 CustomStringConvertible#
    let width: Double
//      ^^^^^ definition scip-swift swiftpm HierCore . Rect#`width=`().
//            kind Setter
//            display_name HierCore.Rect.width.setter : Swift.Double
//            signature_documentation
//            > func setter:width
//      ^^^^^ definition scip-swift swiftpm HierCore . Rect#width().
//            kind Getter
//            display_name HierCore.Rect.width.getter : Swift.Double
//            signature_documentation
//            > func getter:width
//      ^^^^^ definition scip-swift swiftpm HierCore . Rect#width.
//            kind Property
//            display_name HierCore.Rect.width : Swift.Double
//            signature_documentation
//            > var width
//             ^^^^^^ reference scip-swift swift Swift 6.2.4 Double#
    let height: Double
//      ^^^^^^ definition scip-swift swiftpm HierCore . Rect#`height=`().
//             kind Setter
//             display_name HierCore.Rect.height.setter : Swift.Double
//             signature_documentation
//             > func setter:height
//      ^^^^^^ definition scip-swift swiftpm HierCore . Rect#height().
//             kind Getter
//             display_name HierCore.Rect.height.getter : Swift.Double
//             signature_documentation
//             > func getter:height
//      ^^^^^^ definition scip-swift swiftpm HierCore . Rect#height.
//             kind Property
//             display_name HierCore.Rect.height : Swift.Double
//             signature_documentation
//             > var height
//              ^^^^^^ reference scip-swift swift Swift 6.2.4 Double#
  
    var area: Double { width * height }
//      ^^^^ definition scip-swift swiftpm HierCore . Rect#area.
//           kind Property
//           display_name HierCore.Rect.area : Swift.Double
//           signature_documentation
//           > var area
//           relationship scip-swift swiftpm HierCore . HierShape#area. implementation reference
//            ^^^^^^ reference scip-swift swift Swift 6.2.4 Double#
//                   ^ definition scip-swift swiftpm HierCore . Rect#area().
//                     kind Getter
//                     display_name HierCore.Rect.area.getter : Swift.Double
//                     signature_documentation
//                     > func getter:area
//                     ^^^^^ reference scip-swift swiftpm HierCore . Rect#width().
//                     ^^^^^ reference scip-swift swiftpm HierCore . Rect#width.
//                           ^ reference scip-swift swift Swift 6.2.4 Double#`*`().
//                             ^^^^^^ reference scip-swift swiftpm HierCore . Rect#height().
//                             ^^^^^^ reference scip-swift swiftpm HierCore . Rect#height.
  
    var description: String { "rect \(width)x\(height)" }
//      ^^^^^^^^^^^ definition scip-swift swiftpm HierCore . Rect#description.
//                  kind Property
//                  display_name HierCore.Rect.description : Swift.String
//                  signature_documentation
//                  > var description
//                  relationship scip-swift swift Swift 6.2.4 CustomStringConvertible#description. implementation reference
//                   ^^^^^^ reference scip-swift swift Swift 6.2.4 String#
//                          ^ definition scip-swift swiftpm HierCore . Rect#description().
//                            kind Getter
//                            display_name HierCore.Rect.description.getter : Swift.String
//                            signature_documentation
//                            > func getter:description
//                            ^ reference scip-swift swift Swift 6.2.4 String#init().
//                                    ^^^^^ reference scip-swift swiftpm HierCore . Rect#width().
//                                    ^^^^^ reference scip-swift swiftpm HierCore . Rect#width.
//                                             ^^^^^^ reference scip-swift swiftpm HierCore . Rect#height().
//                                             ^^^^^^ reference scip-swift swiftpm HierCore . Rect#height.
  
    static func == (lhs: Rect, rhs: Rect) -> Bool {
//              ^^ definition scip-swift swiftpm HierCore . Rect#`==`().
//                 kind StaticMethod
//                 display_name static HierCore.Rect.== infix(HierCore.Rect, HierCore.Rect) -> Swift.Bool
//                 signature_documentation
//                 > static func ==(_:_:)
//                 relationship scip-swift swift Swift 6.2.4 Equatable#`==`(). implementation reference
//                  ^^^ definition scip-swift swiftpm HierCore . `s:8HierCore4RectV2eeoiySbAC_ACtFZ3lhsL_ACvp`.
//                      kind Parameter
//                      display_name lhs #1 : HierCore.Rect in static HierCore.Rect.== infix(HierCore.Rect, HierCore.Rect) -> Swift.Bool
//                       ^^^^ reference scip-swift swiftpm HierCore . Rect#
//                             ^^^ definition scip-swift swiftpm HierCore . `s:8HierCore4RectV2eeoiySbAC_ACtFZ3rhsL_ACvp`.
//                                 kind Parameter
//                                 display_name rhs #1 : HierCore.Rect in static HierCore.Rect.== infix(HierCore.Rect, HierCore.Rect) -> Swift.Bool
//                                  ^^^^ reference scip-swift swiftpm HierCore . Rect#
//                                           ^^^^ reference scip-swift swift Swift 6.2.4 Bool#
      lhs.width == rhs.width && lhs.height == rhs.height
//    ^^^ reference scip-swift swiftpm HierCore . `s:8HierCore4RectV2eeoiySbAC_ACtFZ3lhsL_ACvp`.
//        ^^^^^ reference scip-swift swiftpm HierCore . Rect#width().
//        ^^^^^ reference scip-swift swiftpm HierCore . Rect#width.
//              ^^ reference scip-swift swift Swift 6.2.4 Equatable#`==`().
//                 ^^^ reference scip-swift swiftpm HierCore . `s:8HierCore4RectV2eeoiySbAC_ACtFZ3rhsL_ACvp`.
//                     ^^^^^ reference scip-swift swiftpm HierCore . Rect#width().
//                     ^^^^^ reference scip-swift swiftpm HierCore . Rect#width.
//                           ^^ reference scip-swift swift Swift 6.2.4 Bool#`&&`().
//                              ^^^ reference scip-swift swiftpm HierCore . `s:8HierCore4RectV2eeoiySbAC_ACtFZ3lhsL_ACvp`.
//                                  ^^^^^^ reference scip-swift swiftpm HierCore . Rect#height().
//                                  ^^^^^^ reference scip-swift swiftpm HierCore . Rect#height.
//                                         ^^ reference scip-swift swift Swift 6.2.4 Equatable#`==`().
//                                            ^^^ reference scip-swift swiftpm HierCore . `s:8HierCore4RectV2eeoiySbAC_ACtFZ3rhsL_ACvp`.
//                                                ^^^^^^ reference scip-swift swiftpm HierCore . Rect#height().
//                                                ^^^^^^ reference scip-swift swiftpm HierCore . Rect#height.
    }
  
    func draw() {}
//       ^^^^ definition scip-swift swiftpm HierCore . Rect#draw().
//            kind Method
//            display_name HierCore.Rect.draw() -> ()
//            signature_documentation
//            > func draw()
//            relationship scip-swift swiftpm HierCore . HierDrawable#draw(). implementation reference
  }
  
  class BaseWidget {
//      ^^^^^^^^^^ definition scip-swift swiftpm HierCore . BaseWidget#
//                 kind Class
//                 display_name HierCore.BaseWidget
//                 signature_documentation
//                 > class BaseWidget
    var frame: String = "0,0,0,0"
//      ^^^^^ definition scip-swift swiftpm HierCore . BaseWidget#`frame=`().
//            kind Setter
//            display_name HierCore.BaseWidget.frame.setter : Swift.String
//            signature_documentation
//            > func setter:frame
//      ^^^^^ definition scip-swift swiftpm HierCore . BaseWidget#frame().
//            kind Getter
//            display_name HierCore.BaseWidget.frame.getter : Swift.String
//            signature_documentation
//            > func getter:frame
//      ^^^^^ definition scip-swift swiftpm HierCore . BaseWidget#frame.
//            kind Property
//            display_name HierCore.BaseWidget.frame : Swift.String
//            signature_documentation
//            > var frame
//             ^^^^^^ reference scip-swift swift Swift 6.2.4 String#
  
    init() {}
//  ^^^^ definition scip-swift swiftpm HierCore . BaseWidget#init().
//       kind Constructor
//       display_name HierCore.BaseWidget.init() -> HierCore.BaseWidget
//       signature_documentation
//       > init init()
  
    func render() {}
//       ^^^^^^ definition scip-swift swiftpm HierCore . BaseWidget#render().
//              kind Method
//              display_name HierCore.BaseWidget.render() -> ()
//              signature_documentation
//              > func render()
  }
  
  class Square: BaseWidget {
//      ^^^^^^ definition scip-swift swiftpm HierCore . Square#
//             kind Class
//             display_name HierCore.Square
//             signature_documentation
//             > class Square
//             relationship scip-swift swiftpm HierCore . BaseWidget# implementation
//              ^^^^^^^^^^ reference scip-swift swiftpm HierCore . BaseWidget#
    let side: Double
//      ^^^^ definition scip-swift swiftpm HierCore . Square#`side=`().
//           kind Setter
//           display_name HierCore.Square.side.setter : Swift.Double
//           signature_documentation
//           > func setter:side
//      ^^^^ definition scip-swift swiftpm HierCore . Square#side().
//           kind Getter
//           display_name HierCore.Square.side.getter : Swift.Double
//           signature_documentation
//           > func getter:side
//      ^^^^ definition scip-swift swiftpm HierCore . Square#side.
//           kind Property
//           display_name HierCore.Square.side : Swift.Double
//           signature_documentation
//           > var side
//            ^^^^^^ reference scip-swift swift Swift 6.2.4 Double#
  
    override init() {
//           ^^^^ definition scip-swift swiftpm HierCore . Square#init().
//                kind Constructor
//                display_name HierCore.Square.init() -> HierCore.Square
//                signature_documentation
//                > init init()
//                relationship scip-swift swiftpm HierCore . BaseWidget#init(). implementation reference
      side = 1
//    ^^^^ reference scip-swift swiftpm HierCore . Square#`side=`().
//    ^^^^ reference scip-swift swiftpm HierCore . Square#side.
      super.init()
//          ^^^^ reference scip-swift swiftpm HierCore . BaseWidget#init().
    }
  
    override var frame: String {
//               ^^^^^ definition scip-swift swiftpm HierCore . Square#frame.
//                     kind Property
//                     display_name HierCore.Square.frame : Swift.String
//                     signature_documentation
//                     > var frame
//                     relationship scip-swift swiftpm HierCore . BaseWidget#frame. implementation reference
//                      ^^^^^^ reference scip-swift swift Swift 6.2.4 String#
      get { "square" }
//    ^^^ definition scip-swift swiftpm HierCore . Square#frame().
//        kind Getter
//        display_name HierCore.Square.frame.getter : Swift.String
//        signature_documentation
//        > func getter:frame
//        relationship scip-swift swiftpm HierCore . BaseWidget#frame(). implementation reference
      set {}
//    ^^^ definition scip-swift swiftpm HierCore . Square#`frame=`().
//        kind Setter
//        display_name HierCore.Square.frame.setter : Swift.String
//        signature_documentation
//        > func setter:frame
//        relationship scip-swift swiftpm HierCore . BaseWidget#`frame=`(). implementation reference
    }
  
    override func render() {}
//                ^^^^^^ definition scip-swift swiftpm HierCore . Square#render().
//                       kind Method
//                       display_name HierCore.Square.render() -> ()
//                       signature_documentation
//                       > func render()
//                       relationship scip-swift swiftpm HierCore . BaseWidget#render(). implementation reference
  }
  
  class RoundedSquare: Square {
//      ^^^^^^^^^^^^^ definition scip-swift swiftpm HierCore . RoundedSquare#
//                    kind Class
//                    display_name HierCore.RoundedSquare
//                    signature_documentation
//                    > class RoundedSquare
//                    relationship scip-swift swiftpm HierCore . Square# implementation
//                     ^^^^^^ reference scip-swift swiftpm HierCore . Square#
//                            ^ definition scip-swift swiftpm HierCore . RoundedSquare#init().
//                              kind Constructor
//                              display_name HierCore.RoundedSquare.init() -> HierCore.RoundedSquare
//                              signature_documentation
//                              > init init()
//                              relationship scip-swift swiftpm HierCore . Square#init(). implementation reference
    override func render() {}
//                ^^^^^^ definition scip-swift swiftpm HierCore . RoundedSquare#render().
//                       kind Method
//                       display_name HierCore.RoundedSquare.render() -> ()
//                       signature_documentation
//                       > func render()
//                       relationship scip-swift swiftpm HierCore . Square#render(). implementation reference
  }
  
  extension HierShape {
//          ^^^^^^^^^ reference scip-swift swiftpm HierCore . HierShape#
//          ^^^^^^^^^ definition scip-swift swiftpm HierCore . `s:e:s:8HierCore0A5ShapePAAE8describeSSyF`.
//                    kind Extension
//                    display_name HierShape
//                    signature_documentation
//                    > extension HierShape
    func describe() -> String { "shape" }
//       ^^^^^^^^ definition scip-swift swiftpm HierCore . `s:8HierCore0A5ShapePAAE8describeSSyF`.
//                kind Method
//                display_name (extension in HierCore):HierCore.HierShape.describe() -> Swift.String
//                signature_documentation
//                > func describe()
//                relationship scip-swift swiftpm HierCore . HierShape#describe(). implementation reference
//                     ^^^^^^ reference scip-swift swift Swift 6.2.4 String#
  }
  
  public struct Wheel {
//              ^^^^^ definition scip-swift swiftpm HierCore . Wheel#
//                    kind Struct
//                    display_name HierCore.Wheel
//                    signature_documentation
//                    > struct Wheel
//                    relationship scip-swift swiftpm HierCore . HierShape# implementation
    public let spokes: Int
//             ^^^^^^ definition scip-swift swiftpm HierCore . Wheel#`spokes=`().
//                    kind Setter
//                    display_name HierCore.Wheel.spokes.setter : Swift.Int
//                    signature_documentation
//                    > func setter:spokes
//             ^^^^^^ definition scip-swift swiftpm HierCore . Wheel#spokes().
//                    kind Getter
//                    display_name HierCore.Wheel.spokes.getter : Swift.Int
//                    signature_documentation
//                    > func getter:spokes
//             ^^^^^^ definition scip-swift swiftpm HierCore . Wheel#spokes.
//                    kind Property
//                    display_name HierCore.Wheel.spokes : Swift.Int
//                    signature_documentation
//                    > var spokes
//                     ^^^ reference scip-swift swift Swift 6.2.4 Int#
  
    public init(spokes: Int) {
//         ^^^^ definition scip-swift swiftpm HierCore . Wheel#init().
//              kind Constructor
//              display_name HierCore.Wheel.init(spokes: Swift.Int) -> HierCore.Wheel
//              signature_documentation
//              > init init(spokes:)
//              ^^^^^^ definition scip-swift swiftpm HierCore . `s:8HierCore5WheelV6spokesACSi_tcfcADL_Sivp`.
//                     kind Parameter
//                     display_name spokes #1 : Swift.Int in HierCore.Wheel.init(spokes: Swift.Int) -> HierCore.Wheel
//                      ^^^ reference scip-swift swift Swift 6.2.4 Int#
      self.spokes = spokes
//         ^^^^^^ reference scip-swift swiftpm HierCore . Wheel#`spokes=`().
//         ^^^^^^ reference scip-swift swiftpm HierCore . Wheel#spokes.
//                  ^^^^^^ reference scip-swift swiftpm HierCore . `s:8HierCore5WheelV6spokesACSi_tcfcADL_Sivp`.
    }
  }
  
  struct Wrapper<T> {
//       ^^^^^^^ definition scip-swift swiftpm HierCore . Wrapper#
//               kind Struct
//               display_name HierCore.Wrapper
//               signature_documentation
//               > struct Wrapper
//               relationship scip-swift swiftpm HierCore . HierDrawable# implementation
//               relationship scip-swift swiftpm HierCore . HierShape# implementation
//       ^^^^^^^ definition scip-swift swiftpm HierCore . Wrapper#init().
//               kind Constructor
//               display_name HierCore.Wrapper.init(inner: A) -> HierCore.Wrapper<A>
//               signature_documentation
//               > init init(inner:)
//               ^ definition scip-swift swiftpm HierCore . Wrapper#T#
//                 kind TypeAlias
//                 display_name HierCore.Wrapper.T
//                 signature_documentation
//                 > typealias T
    let inner: T
//      ^^^^^ definition scip-swift swiftpm HierCore . Wrapper#`inner=`().
//            kind Setter
//            display_name HierCore.Wrapper.inner.setter : A
//            signature_documentation
//            > func setter:inner
//      ^^^^^ definition scip-swift swiftpm HierCore . Wrapper#inner().
//            kind Getter
//            display_name HierCore.Wrapper.inner.getter : A
//            signature_documentation
//            > func getter:inner
//      ^^^^^ definition scip-swift swiftpm HierCore . Wrapper#inner.
//            kind Property
//            display_name HierCore.Wrapper.inner : A
//            signature_documentation
//            > var inner
//             ^ reference scip-swift swiftpm HierCore . Wrapper#T#
  }
  
  /// The D-21 ObjC-rooted superclass gap: NSObject-rooted clauses record no store `baseOf`;
  /// 04-02's bounded SwiftSyntax fallback supplies the superclass edge.
  class ObjCAnimal: NSObject {
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(pl)NSObject(im)autorelease`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(pl)NSObject(im)class`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(pl)NSObject(im)conformsToProtocol:`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(pl)NSObject(im)isEqual:`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(pl)NSObject(im)isKindOfClass:`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(pl)NSObject(im)isMemberOfClass:`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(pl)NSObject(im)isProxy`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(pl)NSObject(im)performSelector:`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(pl)NSObject(im)performSelector:withObject:`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(pl)NSObject(im)performSelector:withObject:withObject:`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(pl)NSObject(im)release`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(pl)NSObject(im)respondsToSelector:`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(pl)NSObject(im)retainCount`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(pl)NSObject(im)retain`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(pl)NSObject(im)self`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(pl)NSObject(im)zone`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(pl)NSObject(py)debugDescription`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(pl)NSObject(py)description`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(pl)NSObject(py)hash`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(pl)NSObject(py)superclass`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `s:So8NSObjectC10ObjectiveCE2eeoiySbAB_ABtFZ`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `s:So8NSObjectC10ObjectiveCE4hash4intoys6HasherVz_tF`.
//      ^^^^^^^^^^ reference scip-swift swiftpm HierCore . `s:So8NSObjectC10ObjectiveCE9hashValueSivp`.
//      ^^^^^^^^^^ definition scip-swift swiftpm HierCore@objc(cs)ObjCAnimal . `HierCore@objc(cs)ObjCAnimal`#
//                 kind Class
//                 display_name ObjCAnimal
//                 signature_documentation
//                 > class ObjCAnimal
//                 documentation
//                 > The D-21 ObjC-rooted superclass gap: NSObject-rooted clauses record no store `baseOf`;
//                 > 04-02's bounded SwiftSyntax fallback supplies the superclass edge.
//                 relationship scip-swift swiftpm HierCore . `c:objc(cs)NSObject`. implementation
//                  ^^^^^^^^ reference scip-swift swiftpm HierCore . `c:objc(cs)NSObject`.
//                           ^ definition scip-swift swiftpm HierCore@objc(cs)ObjCAnimal(im)init . init().
//                             kind Constructor
//                             display_name init()
//                             signature_documentation
//                             > init init()
//                             relationship scip-swift swiftpm HierCore . `c:objc(cs)NSObject(im)init`. implementation reference
    @objc func sound() -> String { "generic" }
//             ^^^^^ definition scip-swift swiftpm HierCore@objc(cs)ObjCAnimal(im)sound . `HierCore@objc(cs)ObjCAnimal(im)sound`().
//                   kind Method
//                   display_name sound()
//                   signature_documentation
//                   > func sound()
//                        ^^^^^^ reference scip-swift swift Swift 6.2.4 String#
  }
  
  struct 🎨: HierShape {
//       ^^^^ reference scip-swift swiftpm HierCore . `s:8HierCore0A5ShapePAAE8describeSSyF`.
//       ^^^^ definition scip-swift swiftpm HierCore . `🎨`#
//            kind Struct
//            display_name HierCore.🎨
//            signature_documentation
//            > struct 🎨
//            relationship scip-swift swiftpm HierCore . HierShape# implementation
//       ^^^^ definition scip-swift swiftpm HierCore . `🎨`#init().
//            kind Constructor
//            display_name HierCore.🎨.init() -> HierCore.🎨
//            signature_documentation
//            > init init()
//             ^^^^^^^^^ reference scip-swift swiftpm HierCore . HierShape#
    var area: Double { 0 }
//      ^^^^ definition scip-swift swiftpm HierCore . `🎨`#area.
//           kind Property
//           display_name HierCore.🎨.area : Swift.Double
//           signature_documentation
//           > var area
//           relationship scip-swift swiftpm HierCore . HierShape#area. implementation reference
//            ^^^^^^ reference scip-swift swift Swift 6.2.4 Double#
//                   ^ definition scip-swift swiftpm HierCore . `🎨`#area().
//                     kind Getter
//                     display_name HierCore.🎨.area.getter : Swift.Double
//                     signature_documentation
//                     > func getter:area
  
    func draw() {}
//       ^^^^ definition scip-swift swiftpm HierCore . `🎨`#draw().
//            kind Method
//            display_name HierCore.🎨.draw() -> ()
//            signature_documentation
//            > func draw()
//            relationship scip-swift swiftpm HierCore . HierDrawable#draw(). implementation reference
  }
  
  func drawAll(_ items: [HierDrawable]) {
//     ^^^^^^^ definition scip-swift swiftpm HierCore . drawAll().
//             kind Function
//             display_name HierCore.drawAll([HierCore.HierDrawable]) -> ()
//             signature_documentation
//             > func drawAll(_:)
//               ^^^^^ definition local items
//                     kind Parameter
//                     display_name items
//                     enclosing_symbol scip-swift swiftpm HierCore . drawAll().
//                       ^^^^^^^^^^^^ reference scip-swift swiftpm HierCore . HierDrawable#
    for item in items {
      item.draw()
//         ^^^^ reference scip-swift swiftpm HierCore . HierDrawable#draw().
    }
  }
  
  func renderWidget(_ widget: BaseWidget) {
//     ^^^^^^^^^^^^ definition scip-swift swiftpm HierCore . renderWidget().
//                  kind Function
//                  display_name HierCore.renderWidget(HierCore.BaseWidget) -> ()
//                  signature_documentation
//                  > func renderWidget(_:)
//                    ^^^^^^ definition local widget_1
//                           kind Parameter
//                           display_name widget
//                           enclosing_symbol scip-swift swiftpm HierCore . renderWidget().
//                            ^^^^^^^^^^ reference scip-swift swiftpm HierCore . BaseWidget#
    widget.render()
//         ^^^^^^ reference scip-swift swiftpm HierCore . BaseWidget#render().
  }
  
  public func coreDriver() {
//            ^^^^^^^^^^ definition scip-swift swiftpm HierCore . coreDriver().
//                       kind Function
//                       display_name HierCore.coreDriver() -> ()
//                       signature_documentation
//                       > func coreDriver()
    let circle = Circle(radius: 1)
//               ^^^^^^ reference scip-swift swiftpm HierCore . Circle#
//               ^^^^^^ reference scip-swift swiftpm HierCore . Circle#init().
//                      ^^^^^^ reference scip-swift swiftpm HierCore . Circle#radius.
    drawAll([circle])
//  ^^^^^^^ reference scip-swift swiftpm HierCore . drawAll().
//          ^ reference scip-swift swiftpm HierCore . `s:Sa12arrayLiteralSayxGxd_tcfc`.
  }
  
  extension Wheel: HierShape {
//          ^^^^^ reference scip-swift swiftpm HierCore . Wheel#
//          ^^^^^ reference scip-swift swiftpm HierCore . `s:8HierCore0A5ShapePAAE8describeSSyF`.
//          ^^^^^ definition scip-swift swiftpm HierCore . `s:e:s:8HierCore5WheelV4areaSdvp`.
//                kind Extension
//                display_name Wheel
//                signature_documentation
//                > extension Wheel
//                 ^^^^^^^^^ reference scip-swift swiftpm HierCore . HierShape#
    var area: Double { Double(spokes) }
//      ^^^^ definition scip-swift swiftpm HierCore . Wheel#area.
//           kind Property
//           display_name HierCore.Wheel.area : Swift.Double
//           signature_documentation
//           > var area
//           relationship scip-swift swiftpm HierCore . HierShape#area. implementation reference
//            ^^^^^^ reference scip-swift swift Swift 6.2.4 Double#
//                   ^ definition scip-swift swiftpm HierCore . Wheel#area().
//                     kind Getter
//                     display_name HierCore.Wheel.area.getter : Swift.Double
//                     signature_documentation
//                     > func getter:area
//                     ^^^^^^ reference scip-swift swift Swift 6.2.4 Double#
//                     ^^^^^^ reference scip-swift swiftpm HierCore . `s:SdySdSicfc`.
//                            ^^^^^^ reference scip-swift swiftpm HierCore . Wheel#spokes().
//                            ^^^^^^ reference scip-swift swiftpm HierCore . Wheel#spokes.
  
    func draw() {}
//       ^^^^ definition scip-swift swiftpm HierCore . Wheel#draw().
//            kind Method
//            display_name HierCore.Wheel.draw() -> ()
//            signature_documentation
//            > func draw()
//            relationship scip-swift swiftpm HierCore . HierDrawable#draw(). implementation reference
  }
  
  extension Wrapper: HierShape, HierDrawable where T: HierShape {
//          ^^^^^^^ reference scip-swift swiftpm HierCore . Wrapper#
//          ^^^^^^^ reference scip-swift swiftpm HierCore . `s:8HierCore0A5ShapePAAE8describeSSyF`.
//          ^^^^^^^ definition scip-swift swiftpm HierCore . `s:e:s:8HierCore7WrapperVA2A0A5ShapeRzlE4areaSdvp`.
//                  kind Extension
//                  display_name Wrapper
//                  signature_documentation
//                  > extension Wrapper
//                   ^^^^^^^^^ reference scip-swift swiftpm HierCore . HierShape#
//                              ^^^^^^^^^^^^ reference scip-swift swiftpm HierCore . HierDrawable#
//                                                 ^ reference scip-swift swiftpm HierCore . Wrapper#T#
//                                                    ^^^^^^^^^ reference scip-swift swiftpm HierCore . HierShape#
    var area: Double { inner.area }
//      ^^^^ definition scip-swift swiftpm HierCore . `s:8HierCore7WrapperVA2A0A5ShapeRzlE4areaSdvp`.
//           kind Property
//           display_name (extension in HierCore):HierCore.Wrapper<A where A: HierCore.HierShape>.area : Swift.Double
//           signature_documentation
//           > var area
//           relationship scip-swift swiftpm HierCore . HierShape#area. implementation reference
//            ^^^^^^ reference scip-swift swift Swift 6.2.4 Double#
//                   ^ definition scip-swift swiftpm HierCore . `s:8HierCore7WrapperVA2A0A5ShapeRzlE4areaSdvg`.
//                     kind Getter
//                     display_name (extension in HierCore):HierCore.Wrapper<A where A: HierCore.HierShape>.area.getter : Swift.Double
//                     signature_documentation
//                     > func getter:area
//                     ^^^^^ reference scip-swift swiftpm HierCore . Wrapper#inner().
//                     ^^^^^ reference scip-swift swiftpm HierCore . Wrapper#inner.
//                           ^^^^ reference scip-swift swiftpm HierCore . HierShape#area().
//                           ^^^^ reference scip-swift swiftpm HierCore . HierShape#area.
  
    func draw() { inner.draw() }
//       ^^^^ definition scip-swift swiftpm HierCore . `s:8HierCore7WrapperVA2A0A5ShapeRzlE4drawyyF`.
//            kind Method
//            display_name (extension in HierCore):HierCore.Wrapper<A where A: HierCore.HierShape>.draw() -> ()
//            signature_documentation
//            > func draw()
//            relationship scip-swift swiftpm HierCore . HierDrawable#draw(). implementation reference
//                ^^^^^ reference scip-swift swiftpm HierCore . Wrapper#inner().
//                ^^^^^ reference scip-swift swiftpm HierCore . Wrapper#inner.
//                      ^^^^ reference scip-swift swiftpm HierCore . HierDrawable#draw().
  }
  
