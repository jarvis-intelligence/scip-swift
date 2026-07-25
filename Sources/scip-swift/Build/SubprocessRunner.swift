import Foundation

/// Single-write-then-read box for handing a `Data` value from a background read to the thread
/// that called `readGroup.wait()`. Safe because the write always happens-before the wait returns.
private final class DataBox: @unchecked Sendable {
  var value = Data()
}

/// Thin wrapper around `Process` for invoking build-tool executables and capturing output.
enum SubprocessRunner {
  struct Result {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    /// stdout+stderr concatenated: both `swift build` and `xcodebuild` print their own compiler
    /// diagnostics to stdout, not stderr, so error messages should show both.
    var combinedOutput: String {
      [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }
  }

  static func run(executable: String, arguments: [String], currentDirectory: String) throws -> Result {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
      try process.run()
    } catch {
      throw BuildError.toolNotLaunchable(tool: executable, underlying: error.localizedDescription)
    }

    // Read both pipes concurrently: reading them sequentially can deadlock if the process fills
    // one pipe's kernel buffer while we're still blocked reading the other. `DataBox` is only
    // mutated before `readGroup.wait()` returns and only read after, so the access is safe despite
    // not being visible to the compiler's data-race checker.
    let stdoutBox = DataBox()
    let stderrBox = DataBox()
    let readGroup = DispatchGroup()
    readGroup.enter()
    DispatchQueue.global().async {
      stdoutBox.value = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
      readGroup.leave()
    }
    readGroup.enter()
    DispatchQueue.global().async {
      stderrBox.value = stderrPipe.fileHandleForReading.readDataToEndOfFile()
      readGroup.leave()
    }
    readGroup.wait()
    process.waitUntilExit()

    return Result(
      exitCode: process.terminationStatus,
      stdout: String(decoding: stdoutBox.value, as: UTF8.self),
      stderr: String(decoding: stderrBox.value, as: UTF8.self)
    )
  }

  /// Resolves an executable name (e.g. "swift", "xcodebuild") to an absolute path via `/usr/bin/env`,
  /// mirroring shell `PATH` lookup.
  static func resolveExecutable(named name: String) throws -> String {
    let result = try run(executable: "/usr/bin/env", arguments: ["which", name], currentDirectory: "/")
    let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard result.exitCode == 0, !path.isEmpty else {
      throw BuildError.toolNotLaunchable(tool: name, underlying: "not found on PATH")
    }
    return path
  }
}
