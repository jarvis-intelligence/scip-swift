/// Errors surfaced by the build-index-generation pipeline (Requirement: Build-index generation,
/// Requirement: Platform constraint enforcement).
enum BuildError: Error, CustomStringConvertible {
  /// Neither a `Package.swift` nor an `.xcodeproj`/`.xcworkspace` was found, and no `--build-tool`
  /// override was given.
  case cannotDetectBuildSystem(repoPath: String)

  /// `xcodebuild` was requested but no scheme was given and none could be inferred.
  case xcodebuildSchemeRequired

  /// The build tool executable itself could not be launched (e.g. not installed, or `xcodebuild`
  /// unavailable because the host has no Xcode / no Apple SDKs — see the platform constraint
  /// requirement).
  case toolNotLaunchable(tool: String, underlying: String)

  /// The build tool ran but exited non-zero. `output` combines stdout+stderr: both `swift build`
  /// and `xcodebuild` print their own compiler diagnostics to stdout, not stderr.
  case buildFailed(tool: String, exitCode: Int32, output: String)

  /// The build reported success, but no IndexStore was found where one was expected.
  case indexStoreNotProduced(expectedPath: String)

  var description: String {
    switch self {
    case .cannotDetectBuildSystem(let repoPath):
      return """
        Could not detect a build system at \(repoPath): no Package.swift and no \
        .xcodeproj/.xcworkspace found. Pass --build-tool swiftpm or --build-tool xcodebuild \
        explicitly.
        """
    case .xcodebuildSchemeRequired:
      return "xcodebuild requires --scheme <name> (or a single default scheme could not be inferred)."
    case .toolNotLaunchable(let tool, let underlying):
      return "Could not launch '\(tool)': \(underlying)"
    case .buildFailed(let tool, let exitCode, let output):
      return """
        '\(tool)' failed with exit code \(exitCode):
        \(output)
        """
    case .indexStoreNotProduced(let expectedPath):
      return """
        Build succeeded but no IndexStore was produced at \(expectedPath). This commonly happens \
        when the code being indexed cannot compile on this host (for example, Apple-platform-only \
        imports such as UIKit/WatchKit/WidgetKit on a non-macOS host, or a missing SDK).
        """
    }
  }
}
