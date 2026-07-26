import ArgumentParser

@main
struct ScipSwiftCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "scip-swift",
    abstract: "Converts a Swift repo's IndexStoreDB build index into a real scip.proto SCIP index.",
    version: "\(ScipSwiftVersion.version) (swift \(ToolchainInfo.pinnedSwiftVersion))",
    subcommands: [IndexCommand.self],
    defaultSubcommand: IndexCommand.self
  )
}
