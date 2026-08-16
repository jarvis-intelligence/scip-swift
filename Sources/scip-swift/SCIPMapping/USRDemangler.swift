import Foundation

/// Requirement: demangled human-readable names for `s:`-prefixed USRs (SYMBOL-01/SYMBOL-02).
///
/// Loads the toolchain's own `libswiftDemangle.dylib` in-process and calls its
/// `swift_demangle_getDemangledName` C ABI on Swift USRs, rewriting the `s:` prefix to the
/// `_$s` prefix the demangler expects. Output is display-only: it feeds
/// `SymbolInformation.display_name` and never touches the canonical symbol string.
///
/// A class, not the stateless enum-namespace mapper convention, because it memoizes results
/// across the whole `build()` run.
final class USRDemangler {
  private typealias DemangleFunction = @convention(c) (
    UnsafePointer<CChar>?, UnsafeMutablePointer<CChar>?, UInt
  ) -> UInt

  private let demangle: DemangleFunction
  private var cache: [String: String?] = [:]

  /// Loads the demangler from an explicit dylib path. Returns nil on any failure — missing
  /// dylib, failed dlopen, missing symbol — callers then keep the IndexStoreDB short name.
  init?(dylibPath: String) {
    guard let handle = dlopen(dylibPath, RTLD_LAZY) else { return nil }
    guard let symbol = dlsym(handle, "swift_demangle_getDemangledName") else {
      dlclose(handle)
      return nil
    }
    demangle = unsafeBitCast(symbol, to: DemangleFunction.self)
  }

  /// Resolves the toolchain's `libswiftDemangle.dylib` via `xcrun` and loads it. Returns nil on
  /// any resolution or load failure — indexing must still complete without the demangler
  /// (SYMBOL-02 fail-soft).
  static func load() -> USRDemangler? {
    guard let dylibPath = try? ToolchainInfo.libswiftDemangleDylibPath() else { return nil }
    return USRDemangler(dylibPath: dylibPath)
  }

  /// Demangled display name for a USR, or nil when the input is not a demanglable Swift USR or
  /// the demangler rejects it — the caller keeps the IndexStoreDB short name (SYMBOL-02).
  func demangledDisplayName(usr: String) -> String? {
    // Only Swift USRs are demanglable; c:/so:/_: inputs and closure/local-suffix manglings
    // return 0 from the C ABI, so gate up front rather than shipping them across it.
    guard usr.hasPrefix("s:") else { return nil }
    if let cached = cache[usr] { return cached }

    let result = demangleToBuffer(usr: usr)
    cache[usr] = result
    return result
  }

  private func demangleToBuffer(usr: String) -> String? {
    var mangled = "_$s"
    mangled += usr.dropFirst(2)

    // The ABI writes into a caller-owned buffer — no free() is needed on any exit path — and
    // returns 0 on failure or the full required length when truncated, which is the signal to
    // retry once with a buffer of exactly n+1 bytes.
    var capacity = 64
    var buffer = [CChar](repeating: 0, count: capacity)
    var returned = demangle(mangled, &buffer, UInt(capacity))
    if returned == 0 { return nil }

    if returned >= UInt(capacity) {
      capacity = Int(returned) + 1
      buffer = [CChar](repeating: 0, count: capacity)
      returned = demangle(mangled, &buffer, UInt(capacity))
      if returned == 0 { return nil }
    }

    let output = String(cString: buffer)
    return output.isEmpty ? nil : output
  }
}
