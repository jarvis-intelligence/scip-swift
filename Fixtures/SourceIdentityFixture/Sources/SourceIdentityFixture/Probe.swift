@propertyWrapper
struct Flag {
  var wrappedValue: Bool
  var projectedValue: Bool { wrappedValue }
}

struct Probe: CustomStringConvertible {
  @Flag var selection = false
  var description: String { "probe" }
  func read() -> Bool {
    $selection
  }
}

private struct Rows {
  let first = 1
  let second = 2
  let third = 3
  let fourth = 4
  let fifth = 5
  let sixth = 6
  func sum() -> Int { first + second + third + fourth + fifth + sixth }
}

fileprivate let logger = 1
func readFirst() -> Int { logger + Rows().sum() }
