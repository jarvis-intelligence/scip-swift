import Foundation
import Testing

@testable import scip_swift

@Suite("Declaration and source ranges")
struct SourceRangeTests {
  private func refiner(_ source: String) throws -> SwiftSyntaxRefiner {
    let file = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("ranges-\(UUID().uuidString).swift")
    try source.write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }
    return try #require(SwiftSyntaxRefiner(filePath: file.path))
  }

  @Test("types include attributes and bodies without neighbouring declarations")
  func typeDeclarations() throws {
    for kind in ["struct", "class", "enum", "actor", "protocol"] {
      let source = "// header\n@available(*, deprecated)\n\(kind) Sample {\n}\nlet neighbour = 1"
      let syntax = try refiner(source)
      #expect(syntax.enclosingRange(line: 3, utf8Column: kind.utf8.count + 2) == [1, 0, 3, 1])
      #expect(syntax.enclosingRange(line: 2, utf8Column: 1) == nil)
      #expect(syntax.enclosingRange(line: 5, utf8Column: 1) == nil)
    }
  }

  @Test("methods, initializers, properties and subscripts retain their entire declaration")
  func memberDeclarations() throws {
    let source = """
      extension Sample {
        @inline(__always)
        func run() {
          print("名前")
        }
        init() {
          self.init()
        }
        var value: Int {
          get { 1 }
          set { print(newValue) }
        }
        subscript(i: Int) -> Int {
          value + i
        }
        let 名前 = 1
      }
      """
    let syntax = try refiner(source)
    #expect(syntax.enclosingRange(line: 1, utf8Column: 11) == [0, 0, 16, 1])
    #expect(syntax.enclosingRange(line: 3, utf8Column: 8) == [1, 2, 4, 3])
    #expect(syntax.enclosingRange(line: 6, utf8Column: 3) == [5, 2, 7, 3])
    #expect(syntax.enclosingRange(line: 9, utf8Column: 7) == [8, 2, 11, 3])
    #expect(syntax.enclosingRange(line: 13, utf8Column: 3) == [12, 2, 14, 3])
    #expect(syntax.enclosingRange(line: 16, utf8Column: 7) == [15, 2, 15, 16])
    #expect(syntax.enclosingRange(line: 4, utf8Column: 5) == nil)
  }

  @Test("macro anchors never inherit another declaration's range")
  func syntheticAnchors() throws {
    let syntax = try refiner("@Model\nclass Item {}\n#Preview { Item() }\nfunc next() {}")
    #expect(syntax.enclosingRange(line: 1, utf8Column: 1) == nil)
    #expect(syntax.enclosingRange(line: 3, utf8Column: 1) == nil)
    #expect(syntax.enclosingRange(line: 2, utf8Column: 7) == [0, 0, 1, 13])
    #expect(syntax.enclosingRange(line: 4, utf8Column: 6) == [3, 0, 3, 14])
  }

  @Test("projected identifier interior anchors resolve to the whole UTF-8 token")
  func projectedIdentifiers() throws {
    let syntax = try refiner("use($binding)\nuse($名前)")
    #expect(syntax.tokenRange(line: 1, utf8Column: 6) == 4..<12)
    #expect(syntax.tokenRange(line: 2, utf8Column: 6) == 4..<11)
    #expect(syntax.tokenRange(line: 1, utf8Column: 2) == nil)
  }

  @Test("bounds clamp ends and drop invalid starts, lines and empty ranges")
  func sourceBounds() {
    let bounds = SourceBounds(source: "let 名前 = 1\r\n")
    func range(_ line: Int32, _ start: Int32, _ end: Int32) -> Scip_SingleLineRange {
      var range = Scip_SingleLineRange()
      range.line = line
      range.startCharacter = start
      range.endCharacter = end
      return range
    }
    #expect(bounds.validated(range(0, 4, 90))?.endCharacter == 14)
    #expect(bounds.validated(range(0, 4, 9))?.endCharacter == 7)
    #expect(bounds.validated(range(0, 5, 10)) == nil)
    #expect(bounds.validated(range(0, 15, 20)) == nil)
    #expect(bounds.validated(range(1, 0, 1)) == nil)
    #expect(bounds.validated(range(2, 0, 1)) == nil)
    #expect(bounds.contains(range: [0, 0, 0, 14]))
    #expect(!bounds.contains(range: [0, 0, 0, 15]))
  }
}
