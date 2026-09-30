fileprivate let logger = 3
func readThird() -> Int { logger + Marker().touch() }

private struct Marker {
  var value = 3
  func touch() -> Int { value }
}
