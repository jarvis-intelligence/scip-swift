import ArgumentParser
import Foundation

struct IndexManyCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "index-many",
    abstract: "Index multiple Swift repos independently, optionally merging results."
  )

  @Argument(help: "Paths to Swift repos to index (two or more).")
  var repoPaths: [String]

  @Flag(name: .long, help: "Merge all indexes into a single .scip output.")
  var merge: Bool = false

  @Option(name: .long, help: "Directory for individual .scip file output (when not merging).")
  var outputDir: String?

  @Option(name: .long, help: "Output path for merged .scip file (used with --merge).")
  var mergedOutput: String?

  @Option(name: .long, help: "Build configuration ('debug' or 'release').")
  var configuration: BuildConfiguration = .debug

  @Option(name: .long, help: "Directory for the incremental index cache.")
  var cacheDir: String?

  func run() throws {
    guard repoPaths.count >= 2 else {
      throw ValidationError("index-many requires at least two repository paths.")
    }

    var indexes: [Scip_Index] = []
    var repoIdentifiers: [String] = []

    for repoPath in repoPaths {
      let resolvedPath = URL(fileURLWithPath: repoPath).standardizedFileURL.path
      let repoId = URL(fileURLWithPath: resolvedPath).lastPathComponent
      repoIdentifiers.append(repoId)

      let index = try IndexCommand.indexOneRepo(
        repoPath: resolvedPath,
        output: nil,
        buildTool: nil,
        configuration: configuration,
        scheme: nil,
        cacheDir: cacheDir,
        indexOnly: false,
        symbolVersion: repoId
      )
      indexes.append(index)
      print("Indexed \(resolvedPath): \(index.documents.count) document(s)")
    }

    if merge {
      let merged = ScipIndexMerger.merge(
        indexes,
        repoIdentifiers: repoIdentifiers,
        projectRoot: FileManager.default.currentDirectoryPath
      )
      let outputPath = mergedOutput ?? "merged.scip"
      try merged.serializedData().write(to: URL(fileURLWithPath: outputPath))
      print("Merged \(indexes.count) indexes: \(merged.documents.count) document(s) to \(outputPath)")
    } else {
      let dir = outputDir ?? "."
      for (index, repoId) in zip(indexes, repoIdentifiers) {
        let outputPath = (dir as NSString).appendingPathComponent("\(repoId).scip")
        try index.serializedData().write(to: URL(fileURLWithPath: outputPath))
        print("Wrote \(index.documents.count) document(s) to \(outputPath)")
      }
    }
  }
}
