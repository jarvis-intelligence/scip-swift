import ArgumentParser
import Foundation

struct IndexCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "index",
    abstract: "Converts a Swift repo's IndexStoreDB build index into a real scip.proto SCIP index.",
    version: "\(ScipSwiftVersion.version) (swift \(ToolchainInfo.pinnedSwiftVersion))"
  )

  @Argument(help: "Path to the Swift repo to index.")
  var repoPath: String = FileManager.default.currentDirectoryPath

  @Option(name: .long, help: "Output path for the .scip file. Defaults to <repo>/index.scip.")
  var output: String?

  @Option(name: .long, help: "Build backend to use ('swiftpm' or 'xcodebuild'). Auto-detected when omitted.")
  var buildTool: BuildTool?

  @Option(name: .long, help: "Build configuration ('debug' or 'release').")
  var configuration: BuildConfiguration = .debug

  @Option(name: .long, help: "Xcode scheme to build. Only used with xcodebuild; auto-detected if the project has exactly one scheme.")
  var scheme: String?

  func run() throws {
    let resolvedRepoPath = URL(fileURLWithPath: repoPath).standardizedFileURL.path
    let tool = try buildTool ?? BuildBackendDetector.detect(repoPath: resolvedRepoPath)
    let workDirectory = try Self.makeTemporaryDirectory()

    let buildResult = try produceIndexStore(tool: tool, repoPath: resolvedRepoPath, workDirectory: workDirectory)

    let builder = SCIPIndexBuilder(
      repoPath: resolvedRepoPath,
      indexStorePath: buildResult.indexStorePath,
      databasePath: (workDirectory as NSString).appendingPathComponent("index-db"),
      buildToolName: tool.rawValue,
      converterVersion: ScipSwiftVersion.version
    )
    let index = try builder.build()

    let outputPath = output ?? (resolvedRepoPath as NSString).appendingPathComponent("index.scip")
    try index.serializedData().write(to: URL(fileURLWithPath: outputPath))

    print("Wrote \(index.documents.count) document(s) to \(outputPath)")
  }

  private func produceIndexStore(tool: BuildTool, repoPath: String, workDirectory: String) throws -> IndexStoreBuildResult {
    switch tool {
    case .swiftpm:
      let runner = SwiftPMBuildRunner(
        repoPath: repoPath,
        configuration: configuration,
        scratchPath: (workDirectory as NSString).appendingPathComponent("scratch")
      )
      return try runner.produceIndexStore()

    case .xcodebuild:
      let projectArguments = try XcodeProjectLocator.workspaceOrProjectArguments(repoPath: repoPath)
      let resolvedScheme = try XcodeProjectLocator.resolveScheme(
        explicitScheme: scheme,
        projectArguments: projectArguments,
        repoPath: repoPath
      )
      let runner = XcodebuildBuildRunner(
        repoPath: repoPath,
        configuration: configuration,
        scheme: resolvedScheme,
        derivedDataPath: (workDirectory as NSString).appendingPathComponent("derived-data"),
        projectArguments: projectArguments
      )
      return try runner.produceIndexStore()
    }
  }

  private static func makeTemporaryDirectory() throws -> String {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("scip-swift-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }
}
