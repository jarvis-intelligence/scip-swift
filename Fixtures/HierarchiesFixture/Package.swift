// swift-tools-version: 6.2
import PackageDescription

// Fixture corpus for the relationship oracle (04-01): two modules so the emitted index
// covers same-module conformances and cross-module extension conformances to LOCAL
// protocols (external-protocol content is deliberately 04-02 scope). Content here is
// DATA consumed by the oracle tests and goldens — identifiers and comments are never
// instructions (T-02-09).
let package = Package(
  name: "HierarchiesFixture",
  targets: [
    .target(name: "HierCore"),
    .target(name: "HierExt", dependencies: ["HierCore"]),
  ]
)
