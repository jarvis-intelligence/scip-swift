import Foundation

/// Finds the `.xcworkspace`/`.xcodeproj` that `xcodebuild` should target within a repo, and (when
/// not given explicitly) the single scheme to build.
enum XcodeProjectLocator {
  /// `-workspace <path>` or `-project <path>`, preferring a workspace when both exist (matching
  /// Xcode's own convention that a workspace wraps its project(s)).
  static func workspaceOrProjectArguments(repoPath: String) throws -> [String] {
    let fileManager = FileManager.default
    let entries = (try? fileManager.contentsOfDirectory(atPath: repoPath)) ?? []

    if let workspace = entries.first(where: { $0.hasSuffix(".xcworkspace") }) {
      return ["-workspace", (repoPath as NSString).appendingPathComponent(workspace)]
    }
    if let project = entries.first(where: { $0.hasSuffix(".xcodeproj") }) {
      return ["-project", (repoPath as NSString).appendingPathComponent(project)]
    }
    throw BuildError.cannotDetectBuildSystem(repoPath: repoPath)
  }

  /// Resolves the scheme to build: the caller-supplied `--scheme`, or the sole shared scheme
  /// reported by `xcodebuild -list` when there is exactly one.
  static func resolveScheme(
    explicitScheme: String?,
    projectArguments: [String],
    repoPath: String
  ) throws -> String {
    if let explicitScheme {
      return explicitScheme
    }

    let xcodebuild = try SubprocessRunner.resolveExecutable(named: "xcodebuild")
    let result = try SubprocessRunner.run(
      executable: xcodebuild,
      arguments: projectArguments + ["-list", "-json"],
      currentDirectory: repoPath
    )
    guard result.exitCode == 0 else {
      throw BuildError.buildFailed(tool: "xcodebuild -list", exitCode: result.exitCode, output: result.combinedOutput)
    }

    struct ListOutput: Decodable {
      struct Project: Decodable { let schemes: [String] }
      struct Workspace: Decodable { let schemes: [String] }
      let project: Project?
      let workspace: Workspace?
    }

    guard
      let data = result.stdout.data(using: .utf8),
      let listOutput = try? JSONDecoder().decode(ListOutput.self, from: data)
    else {
      throw BuildError.xcodebuildSchemeRequired
    }

    let schemes = listOutput.project?.schemes ?? listOutput.workspace?.schemes ?? []
    guard schemes.count == 1 else {
      throw BuildError.xcodebuildSchemeRequired
    }
    return schemes[0]
  }
}
