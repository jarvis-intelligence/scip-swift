public protocol Shape {
  func area() -> Int
}
public protocol OtherShape {
  func area() -> Int
}
public struct Square: Shape {
  public func area() -> Int { 4 }
}
public struct Circle {
  public func area() -> Int { 3 }
}
extension Circle: Shape {}
public struct Remote {
  public func area() -> Int { 2 }
}
public struct Early {
  public func area() -> Int { 1 }
}
public struct Unrelated {
  public func area() -> Int { 0 }
}
