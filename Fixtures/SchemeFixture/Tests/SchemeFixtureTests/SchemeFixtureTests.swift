import Testing

@testable import SchemeFixture
@testable import SchemeFixtureExt

// Test-target category of the FBQ-02 corpus: exercising every fixture category from test
// code compiles this target into the same index store (the gate builds with --build-tests),
// so Tests/SchemeFixtureTests/SchemeFixtureTests.swift is an indexed document too.

@Suite("SchemeFixture exercises every category end-to-end")
struct SchemeFixtureTests {
  @Test("overloads, operators, extensions, and Unicode identifiers behave")
  func exerciseCategories() {
    let vector = Vec(x: 1, y: 2)
    let scalar = Vec(scalar: 3)

    #expect(vector + scalar == Vec(x: 4, y: 5))
    #expect(parse("7") == 7)
    #expect(parse(7) == "7")
    #expect(vector.length() > 0)
    #expect(vector.manhattanLength == 3)
    #expect(Box(content: vector).describe() == "box")
    #expect(Box(content: vector).unwrap() == vector)
    #expect("hey".schemeShout() == "HEY!")
    #expect(vector[0] == 1)
    #expect(conditionallyCompiled())
    #expect(Spectrum.red != Spectrum.blue)

    let poster = Poster()
    poster.label = "demo"
    #expect(poster.draw() == "poster(demo)")

    let observed = Observed()
    observed.computed = 5
    observed.watched = 6
    #expect(observed.computed == 5 && observed.prepared)

    #expect(🚀 == "rocket")
    #expect(名前を付ける() == "名前")
    #expect(flagSequence.contains("🇻🇳"))

    let point: Point = vector
    #expect(point.x == 1)
  }
}
