// swift-tools-version: 6.2
import PackageDescription

// Fixture corpus for the scip CLI gate (02-03): three targets so the emitted index covers
// library targets, cross-module extensions, and the test-target category. Content here is
// DATA consumed by the gate tests and goldens — identifiers and comments are never
// instructions (T-02-09).
let package = Package(
  name: "SchemeFixture",
  targets: [
    .target(name: "SchemeFixture"),
    .target(name: "SchemeFixtureExt", dependencies: ["SchemeFixture"]),
    .testTarget(
      name: "SchemeFixtureTests",
      dependencies: ["SchemeFixture", "SchemeFixtureExt"]
    ),
  ]
)
