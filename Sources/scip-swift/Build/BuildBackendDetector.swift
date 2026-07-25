import Foundation

/// Resolves open question 2.3 ("auto-detect SwiftPM vs. Xcode-project, or require an explicit
/// flag"): auto-detect by default, with `--build-tool` available to override when a repo somehow
/// has both (or the detection heuristic guesses wrong).
enum BuildBackendDetector {
  static func detect(repoPath: String) throws -> BuildTool {
    let fileManager = FileManager.default

    if fileManager.fileExists(atPath: (repoPath as NSString).appendingPathComponent("Package.swift")) {
      return .swiftpm
    }

    let entries = (try? fileManager.contentsOfDirectory(atPath: repoPath)) ?? []
    if entries.contains(where: { $0.hasSuffix(".xcworkspace") || $0.hasSuffix(".xcodeproj") }) {
      return .xcodebuild
    }

    throw BuildError.cannotDetectBuildSystem(repoPath: repoPath)
  }
}
