import Foundation

/// Requirement: Toolchain version pinning.
enum ToolchainInfo {
  /// The Swift toolchain version this converter is built and tested against (Decision 5 in
  /// design.md — kept in sync with `.swift-version`). Swift's USR format is compiler-version
  /// sensitive, so the mapping in `SCIPSymbolFormatter` is only guaranteed stable against this
  /// version.
  static let pinnedSwiftVersion = "6.2.4"

  /// Locates `libIndexStore.dylib` in the active toolchain (resolved the same way
  /// `IndexStoreDB`'s own test infrastructure does: relative to the `swift` executable's toolchain
  /// root, i.e. `<toolchain>/usr/lib/libIndexStore.dylib`).
  ///
  /// This deliberately uses `xcrun --find swift`, not a plain `PATH` lookup: on macOS,
  /// `/usr/bin/swift` is a thin `xcrun`-managed trampoline, not the real toolchain binary, so
  /// deriving the toolchain root from it directly resolves to the wrong (nonexistent) path.
  static func libIndexStoreDylibPath() throws -> String {
    let xcrun = try SubprocessRunner.resolveExecutable(named: "xcrun")
    let result = try SubprocessRunner.run(executable: xcrun, arguments: ["--find", "swift"], currentDirectory: "/")
    let swiftPath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard result.exitCode == 0, !swiftPath.isEmpty else {
      throw BuildError.toolNotLaunchable(tool: "swift", underlying: "xcrun --find swift failed: \(result.stderr)")
    }

    // .../usr/bin/swift -> .../usr
    let usrRoot = (swiftPath as NSString)
      .deletingLastPathComponent as NSString
    let toolchainUsrRoot = usrRoot.deletingLastPathComponent
    return (toolchainUsrRoot as NSString).appendingPathComponent("lib/libIndexStore.dylib")
  }

  /// Locates `libswiftDemangle.dylib` in the active toolchain, mirroring
  /// `libIndexStoreDylibPath()`'s `xcrun --find swift` toolchain-root derivation.
  static func libswiftDemangleDylibPath() throws -> String {
    let xcrun = try SubprocessRunner.resolveExecutable(named: "xcrun")
    let result = try SubprocessRunner.run(executable: xcrun, arguments: ["--find", "swift"], currentDirectory: "/")
    let swiftPath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard result.exitCode == 0, !swiftPath.isEmpty else {
      throw BuildError.toolNotLaunchable(tool: "swift", underlying: "xcrun --find swift failed: \(result.stderr)")
    }

    // .../usr/bin/swift -> .../usr
    let usrRoot = (swiftPath as NSString)
      .deletingLastPathComponent as NSString
    let toolchainUsrRoot = usrRoot.deletingLastPathComponent
    return (toolchainUsrRoot as NSString).appendingPathComponent("lib/libswiftDemangle.dylib")
  }
}
