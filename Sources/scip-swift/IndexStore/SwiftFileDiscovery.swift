import Foundation

/// Walks a repo for `.swift` source files to query against the IndexStore, skipping build output
/// and dependency-checkout noise directories.
enum SwiftFileDiscovery {
  private static let skippedDirectoryNames: Set<String> = [
    ".build", ".git", ".swiftpm", "DerivedData", "Pods", ".index-build",
  ]

  static func swiftFiles(underRepoPath repoPath: String) -> [String] {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(atPath: repoPath) else { return [] }

    var results: [String] = []
    for case let relativePath as String in enumerator {
      let components = relativePath.split(separator: "/")
      if components.contains(where: { skippedDirectoryNames.contains(String($0)) }) {
        continue
      }
      if relativePath.hasSuffix(".swift") {
        results.append((repoPath as NSString).appendingPathComponent(relativePath))
      }
    }
    return results.sorted()
  }
}
