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

  @Option(name: .long, help: "Directory for the incremental index cache. Defaults to <repo>/.scip-cache/.")
  var cacheDir: String?

  @Flag(name: .long, help: "Skip the build step and read an existing IndexStore directly.")
  var indexOnly: Bool = false

  static let indexstoreDbRevision = "c993f4fb"

  func run() throws {
    let resolvedRepoPath = URL(fileURLWithPath: repoPath).standardizedFileURL.path
    let index = try Self.indexOneRepo(
      repoPath: resolvedRepoPath,
      output: output,
      buildTool: buildTool,
      configuration: configuration,
      scheme: scheme,
      cacheDir: cacheDir,
      indexOnly: indexOnly,
      symbolVersion: ""
    )

    let outputPath = output ?? (resolvedRepoPath as NSString).appendingPathComponent("index.scip")
    try index.serializedData().write(to: URL(fileURLWithPath: outputPath))
    print("Wrote \(index.documents.count) document(s) to \(outputPath)")
  }

  static func indexOneRepo(
    repoPath: String,
    output: String?,
    buildTool: BuildTool?,
    configuration: BuildConfiguration,
    scheme: String?,
    cacheDir: String?,
    indexOnly: Bool,
    symbolVersion: String
  ) throws -> Scip_Index {
    let tool = try buildTool ?? BuildBackendDetector.detect(repoPath: repoPath)

    let persistentCache = cacheDir != nil || indexOnly
    let resolvedCacheDir = cacheDir ?? (repoPath as NSString).appendingPathComponent(".scip-cache")

    let scratchPath: String
    let databasePath: String
    let indexStorePath: String

    if persistentCache {
      try FileManager.default.createDirectory(atPath: resolvedCacheDir, withIntermediateDirectories: true)
      scratchPath = (resolvedCacheDir as NSString).appendingPathComponent("build-scratch")
      databasePath = (resolvedCacheDir as NSString).appendingPathComponent("index-db")

      if indexOnly {
        guard let foundPath = SwiftPMBuildRunner.findIndexStore(
          underScratchPath: scratchPath,
          configuration: configuration
        ) else {
          throw BuildError.indexStoreNotFoundForIndexOnly(
            expectedPath: "\(scratchPath)/<triple>/\(configuration.rawValue)/index/store"
          )
        }
        indexStorePath = foundPath
      } else {
        let runner = SwiftPMBuildRunner(
          repoPath: repoPath,
          configuration: configuration,
          scratchPath: scratchPath
        )
        indexStorePath = try runner.produceIndexStore().indexStorePath
      }
    } else {
      let workDirectory = makeTemporaryDirectory()
      scratchPath = (workDirectory as NSString).appendingPathComponent("scratch")
      databasePath = (workDirectory as NSString).appendingPathComponent("index-db")

      let runner = SwiftPMBuildRunner(
        repoPath: repoPath,
        configuration: configuration,
        scratchPath: scratchPath
      )
      indexStorePath = try runner.produceIndexStore().indexStorePath
    }

    var cacheStore: CacheStore?
    if persistentCache {
      let store = CacheStore(cacheDir: resolvedCacheDir)
      if let manifest = try store.loadManifest() {
        if !manifest.isCompatibleWith(
          toolchainVersion: ToolchainInfo.pinnedSwiftVersion,
          converterVersion: ScipSwiftVersion.version,
          indexstoreDbRevision: indexstoreDbRevision,
          buildToolName: tool.rawValue
        ) {
          try store.invalidateAll()
          try store.saveManifest(IndexManifest(
            toolchainVersion: ToolchainInfo.pinnedSwiftVersion,
            converterVersion: ScipSwiftVersion.version,
            indexstoreDbRevision: indexstoreDbRevision,
            buildToolName: tool.rawValue
          ))
        }
      } else {
        try store.saveManifest(IndexManifest(
          toolchainVersion: ToolchainInfo.pinnedSwiftVersion,
          converterVersion: ScipSwiftVersion.version,
          indexstoreDbRevision: indexstoreDbRevision,
          buildToolName: tool.rawValue
        ))
      }
      cacheStore = store
    }

    let builder = SCIPIndexBuilder(
      repoPath: repoPath,
      indexStorePath: indexStorePath,
      databasePath: databasePath,
      buildToolName: tool.rawValue,
      converterVersion: ScipSwiftVersion.version,
      symbolVersion: symbolVersion,
      cacheStore: cacheStore
    )
    return try builder.build()
  }

  private static func makeTemporaryDirectory() -> String {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("scip-swift-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }
}
