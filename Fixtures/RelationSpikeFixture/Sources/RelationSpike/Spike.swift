public class Animal {
  public func makeSound() -> String { "" }
}

public class Dog: Animal {
  public override func makeSound() -> String { "Woof" }
}

public protocol Greetable {
  func greet() -> String
}

public struct Greeter: Greetable {
  public init() {}
  public func greet() -> String { "Hello" }
}

extension Dog: Greetable {
  public func greet() -> String { "Woof hello" }
}

public protocol Drawable {
  func draw()
}

public protocol Shape: Drawable {
  var area: Double { get }
}

public func outerFunction() {
  let localValue = 42
  print(localValue)
}
