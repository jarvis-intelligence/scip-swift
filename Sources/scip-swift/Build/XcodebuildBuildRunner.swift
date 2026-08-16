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
  var destination: String? = nil

  /// The full `xcodebuild` argument list. Kept pure and separate from
  /// `produceIndexStore()` so it can be asserted on without spawning Xcode.
  var arguments: [String] {
    let xcodeConfiguration = configuration == .debug ? "Debug" : "Release"
    var arguments = projectArguments + [
      "-scheme", scheme,
      "-configuration", xcodeConfiguration,
      "-derivedDataPath", derivedDataPath,
      "COMPILER_INDEX_STORE_ENABLE=YES",
      // An index build never runs, installs, or ships the product — it exists only to write
      // Index.noindex/DataStore. Signing is pure overhead here: forced-signing app-extension
      // targets fail during GatherProvisioningInputs before anything compiles. Do not
      // restore signing. No -destination is passed by default (xcodebuild then targets
      // "My Mac"); --destination opts in for repos whose iOS-only targets need an explicit
      // simulator/device to index at all.
      "CODE_SIGNING_ALLOWED=NO",
      "CODE_SIGNING_REQUIRED=NO",
      "CODE_SIGN_IDENTITY=",
      "CODE_SIGN_ENTITLEMENTS=",
      "build",
    ]
    if let destination {
      let derivedDataIndex = arguments.firstIndex(of: "-derivedDataPath")!
      arguments.insert(contentsOf: ["-destination", destination], at: derivedDataIndex)
    }
    return arguments
  }

  func produceIndexStore() throws -> IndexStoreBuildResult {
    let xcodebuild = try SubprocessRunner.resolveExecutable(named: "xcodebuild")

    let result = try SubprocessRunner.run(
      executable: xcodebuild,
      arguments: arguments,
      currentDirectory: repoPath
    )
    guard result.exitCode == 0 else {
      if let destination {
        let hintCommand = (projectArguments + ["-scheme", scheme, "-showdestinations"])
          .joined(separator: " ")
        throw BuildError.xcodebuildDestinationFailed(
          exitCode: result.exitCode,
          output: result.combinedOutput,
          hintCommand: "xcodebuild \(hintCommand)"
        )
      }
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
