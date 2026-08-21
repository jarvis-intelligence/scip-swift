// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "scip-swift",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "scip-swift", targets: ["scip-swift"])
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/indexstore-db.git", branch: "main"),
    .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "602.0.0"),
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.1"),
  ],
  targets: [
    .executableTarget(
      name: "scip-swift",
      dependencies: [
        .product(name: "IndexStoreDB", package: "indexstore-db"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(
      name: "scip-swiftTests",
      dependencies: ["scip-swift"],
      // Committed `scip snapshot` goldens (02-03, 04-01) are caret-annotated DATA copies
      // of the fixture sources — SwiftPM must not compile them as test sources.
      exclude: ["SchemeFixtureGoldens", "HierarchiesFixtureGoldens"]
    ),
  ]
)
