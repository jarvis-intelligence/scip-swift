public struct Consumer {
  public let label: String

  public init(label: String) {
    self.label = label
  }

  public func consume() -> String {
    "Consumer: \(label)"
  }
}
