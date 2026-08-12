import Testing

@testable import scip_swift

@Suite("Dylib Check Error")
struct DylibCheckTests {
  @Test("xcodeRequired error description contains dylib name")
  func containsDylibName() {
    let error = BuildError.xcodeRequired(dylibPath: "/nonexistent/libIndexStore.dylib")
    #expect(error.description.contains("libIndexStore.dylib"))
  }

  @Test("xcodeRequired error description contains Xcode")
  func containsXcode() {
    let error = BuildError.xcodeRequired(dylibPath: "/nonexistent/libIndexStore.dylib")
    #expect(error.description.contains("Xcode"))
  }

  @Test("xcodeRequired error description contains xcode-select")
  func containsXcodeSelect() {
    let error = BuildError.xcodeRequired(dylibPath: "/nonexistent/libIndexStore.dylib")
    #expect(error.description.contains("xcode-select"))
  }
}
