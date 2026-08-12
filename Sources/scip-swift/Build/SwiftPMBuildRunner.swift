import Foundation

/// Requirement: Build-index generation — SwiftPM repo indexed via `swift build`.
///
/// `swift build` has no `--index-store-path` flag; the index store's location is an
/// implementation detail of the build system. Instead, this runs the build with an
/// explicit `--scratch-path` (so the output root is known) and `--enable-index-store`
/// (so indexing-while-building isn't silently skipped), then locates
/// `<scratch-path>/<triple>/<configuration>/index/store` underneath it.
struct SwiftPMBuildRunner: BuildRunner {
  let repoPath: String
  let configuration: BuildConfiguration
  let scratchPath: String

  func produceIndexStore() throws -> IndexStoreBuildResult {
    let swift = try SubprocessRunner.resolveExecutable(named: "swift")
    let result = try SubprocessRunner.run(
      executable: swift,
      arguments: [
        "build",
        "--configuration", configuration.rawValue,
        "--scratch-path", scratchPath,
        "--enable-index-store",
      ],
      currentDirectory: repoPath
    )
    guard result.exitCode == 0 else {
      throw BuildError.buildFailed(tool: "swift build", exitCode: result.exitCode, output: result.combinedOutput)
    }

    guard let indexStorePath = Self.findIndexStore(underScratchPath: scratchPath, configuration: configuration) else {
      throw BuildError.indexStoreNotProduced(
        expectedPath: "\(scratchPath)/<triple>/\(configuration.rawValue)/index/store"
      )
    }
    return IndexStoreBuildResult(indexStorePath: indexStorePath)
  }

  static func findIndexStore(underScratchPath scratchPath: String, configuration: BuildConfiguration) -> String? {
    let fileManager = FileManager.default
    let tripleDirectories = (try? fileManager.contentsOfDirectory(atPath: scratchPath)) ?? []
    for triple in tripleDirectories {
      let candidate = "\(scratchPath)/\(triple)/\(configuration.rawValue)/index/store"
      var isDirectory: ObjCBool = false
      if fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory), isDirectory.boolValue {
        return candidate
      }
    }
    return nil
  }
}
