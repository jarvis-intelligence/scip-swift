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

  /// An `xcodebuild` build with an explicit `--destination` exited non-zero — usually a
  /// destination specifier that matches no installed simulator/device. `output` combines
  /// stdout+stderr untruncated; `hintCommand` is the copyable command that lists valid
  /// destinations for the project and scheme.
  case xcodebuildDestinationFailed(exitCode: Int32, output: String, hintCommand: String)

  /// The build reported success, but no IndexStore was found where one was expected.
  case indexStoreNotProduced(expectedPath: String)

  /// `libIndexStore.dylib` was not found at the resolved toolchain path. The user needs
  /// Xcode or Command Line Tools installed (DIST-04).
  case xcodeRequired(dylibPath: String)

  /// `--index-only` was used but no IndexStore was found at the expected persistent path.
  case indexStoreNotFoundForIndexOnly(expectedPath: String)

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
    case .xcodebuildDestinationFailed(let exitCode, let output, let hintCommand):
      return """
        'xcodebuild' failed with exit code \(exitCode) for the requested destination:
        \(output)

        Hint: list valid destinations for this scheme with:
          \(hintCommand)
        """
    case .indexStoreNotProduced(let expectedPath):
      return """
        Build succeeded but no IndexStore was produced at \(expectedPath). This commonly happens \
        when the code being indexed cannot compile on this host (for example, Apple-platform-only \
        imports such as UIKit/WatchKit/WidgetKit on a non-macOS host, or a missing SDK).
        """
    case .xcodeRequired(let dylibPath):
      return """
        libIndexStore.dylib was not found at \(dylibPath). scip-swift requires Xcode or \
        Command Line Tools to be installed.

        To fix this:
          1. Install Xcode from the Mac App Store, or run: xcode-select --install
          2. If Xcode is installed but not selected, run: \
        sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
          3. Verify with: xcrun --find swift
        """
    case .indexStoreNotFoundForIndexOnly(let expectedPath):
      return """
        --index-only was used but no IndexStore was found at \(expectedPath). \
        Run scip-swift without --index-only first to build and cache the index store.
        """
    }
  }
}
