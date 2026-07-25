import ArgumentParser

/// The build system used to compile the target repo and produce an IndexStore.
enum BuildTool: String, CaseIterable, ExpressibleByArgument {
  case swiftpm
  case xcodebuild
}
