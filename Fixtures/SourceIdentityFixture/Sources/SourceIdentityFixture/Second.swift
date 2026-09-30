fileprivate let logger = 2
func readSecond() -> Int { logger + Marker().touch() }

private struct Marker {
  var value = 2
  func touch() -> Int { value }
}
