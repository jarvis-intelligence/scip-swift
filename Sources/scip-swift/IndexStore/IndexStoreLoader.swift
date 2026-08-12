import Foundation
import IndexStoreDB

/// Opens the IndexStore a build backend produced, using the active toolchain's
/// `libIndexStore.dylib`.
enum IndexStoreLoader {
  static func open(storePath: String, databasePath: String) throws -> IndexStoreDB {
    let dylibPath = try ToolchainInfo.libIndexStoreDylibPath()
    guard FileManager.default.fileExists(atPath: dylibPath) else {
      throw BuildError.xcodeRequired(dylibPath: dylibPath)
    }
    let library = try IndexStoreLibrary(dylibPath: dylibPath)
    return try IndexStoreDB(
      storePath: storePath,
      databasePath: databasePath,
      library: library,
      waitUntilDoneInitializing: true
    )
  }
}
