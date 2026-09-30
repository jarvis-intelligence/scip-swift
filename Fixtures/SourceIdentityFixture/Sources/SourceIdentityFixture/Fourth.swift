final class Service {
  private let dependencies: Int
  init(dependencies: Int) { self.dependencies = dependencies }
  func read() -> Int { dependencies }
}
