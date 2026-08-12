import CryptoKit
import Foundation

/// Requirement: INCR-03 (per-file document cache keyed by content hash), INCR-04 (staleness detection).
///
/// Stateless SHA256 content hashing via CryptoKit. Used to compute a stable identifier
/// for source file content so that unchanged files can reuse cached `Scip_Document`
/// protobufs across invocations.
enum ContentHasher {
  static func sha256Hex(of filePath: String) throws -> String {
    let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
    return sha256Hex(of: data)
  }

  static func sha256Hex(of data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.compactMap { String(format: "%02x", $0) }.joined()
  }
}
