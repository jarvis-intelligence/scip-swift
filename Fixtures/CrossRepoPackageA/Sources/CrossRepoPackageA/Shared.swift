public struct SharedType {
  public let value: String

  public init(value: String) {
    self.value = value
  }

  public func describe() -> String {
    "Shared: \(value)"
  }
}
