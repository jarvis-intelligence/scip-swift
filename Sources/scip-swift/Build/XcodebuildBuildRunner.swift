import Foundation

/// Requirement: Build-index generation — Xcode-project repo indexed via `xcodebuild`.
///
/// `xcodebuild` has no direct `-index-store-path` flag either; indexing-while-building always
/// writes into `<DerivedData>/Index.noindex/DataStore` (the same location SourceKit-LSP and
/// Xcode's own "jump to definition" read from). This runs the build with an explicit
/// `-derivedDataPath` (so that location is known) and `COMPILER_INDEX_STORE_ENABLE=YES`.
struct XcodebuildBuildRunner: BuildRunner {
  let repoPath: String
  let configuration: BuildConfiguration
  let scheme: String
  let derivedDataPath: String
  let projectArguments: [String]

  func produceIndexStore() throws -> IndexStoreBuildResult {
    let xcodebuild = try SubprocessRunner.resolveExecutable(named: "xcodebuild")
    let xcodeConfiguration = configuration == .debug ? "Debug" : "Release"

    let result = try SubprocessRunner.run(
      executable: xcodebuild,
      arguments: projectArguments + [
        "-scheme", scheme,
        "-configuration", xcodeConfiguration,
        "-derivedDataPath", derivedDataPath,
        "COMPILER_INDEX_STORE_ENABLE=YES",
        "build",
      ],
      currentDirectory: repoPath
    )
    guard result.exitCode == 0 else {
      throw BuildError.buildFailed(tool: "xcodebuild", exitCode: result.exitCode, output: result.combinedOutput)
    }

    let indexStorePath = (derivedDataPath as NSString)
      .appendingPathComponent("Index.noindex/DataStore")
    guard FileManager.default.fileExists(atPath: indexStorePath) else {
      throw BuildError.indexStoreNotProduced(expectedPath: indexStorePath)
    }
    return IndexStoreBuildResult(indexStorePath: indexStorePath)
  }
}
