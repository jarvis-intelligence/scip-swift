import Testing

@testable import scip_swift

@Suite("XcodebuildBuildRunner arguments")
struct XcodebuildBuildRunnerTests {
  private static let projectArguments = ["-project", "My.xcodeproj"]

  private func makeRunner(configuration: BuildConfiguration = .debug) -> XcodebuildBuildRunner {
    XcodebuildBuildRunner(
      repoPath: "/repo",
      configuration: configuration,
      scheme: "My Scheme",
      derivedDataPath: "/tmp/derived-data",
      projectArguments: Self.projectArguments
    )
  }

  /// The value xcodebuild would read for `flag`, i.e. the element right after it.
  private func value(after flag: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else {
      return nil
    }
    return args[index + 1]
  }

  @Test("project arguments lead the list")
  func projectArgumentsLead() {
    #expect(makeRunner().arguments.starts(with: Self.projectArguments))
  }

  @Test("scheme and derived-data path are passed through verbatim")
  func passesThroughSchemeAndDerivedData() {
    let args = makeRunner().arguments
    #expect(value(after: "-scheme", in: args) == "My Scheme")
    #expect(value(after: "-derivedDataPath", in: args) == "/tmp/derived-data")
  }

  @Test("debug and release map to Xcode's capitalized configuration names")
  func mapsConfigurationNames() {
    #expect(value(after: "-configuration", in: makeRunner(configuration: .debug).arguments) == "Debug")
    #expect(value(after: "-configuration", in: makeRunner(configuration: .release).arguments) == "Release")
  }

  @Test("index-store generation is enabled")
  func enablesIndexStore() {
    #expect(makeRunner().arguments.contains("COMPILER_INDEX_STORE_ENABLE=YES"))
  }

  @Test("the build action is the final argument")
  func buildActionIsLast() {
    #expect(makeRunner().arguments.last == "build")
  }

  @Test("code signing is fully disabled — an index build never ships a product")
  func disablesCodeSigning() {
    let args = makeRunner().arguments
    #expect(args.contains("CODE_SIGNING_ALLOWED=NO"))
    #expect(args.contains("CODE_SIGNING_REQUIRED=NO"))
    #expect(args.contains("CODE_SIGN_IDENTITY="))
    #expect(args.contains("CODE_SIGN_ENTITLEMENTS="))
  }

  @Test("signing settings precede the build action")
  func signingSettingsPrecedeBuildAction() {
    let args = makeRunner().arguments
    let lastSetting = args.lastIndex(where: { $0.hasPrefix("CODE_SIGN") })
    let buildAction = args.firstIndex(of: "build")
    #expect(lastSetting != nil)
    #expect(buildAction != nil)
    if let lastSetting, let buildAction {
      #expect(lastSetting < buildAction)
    }
  }
}
