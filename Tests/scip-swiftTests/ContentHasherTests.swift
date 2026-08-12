import Foundation
import Testing

@testable import scip_swift

@Suite("ContentHasher")
struct ContentHasherTests {
  @Test("sha256Hex of empty Data produces known SHA256")
  func emptyDataHash() {
    let hash = ContentHasher.sha256Hex(of: Data())
    #expect(hash == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  }

  @Test("sha256Hex of known content produces known SHA256")
  func knownContentHash() {
    let hash = ContentHasher.sha256Hex(of: "hello".data(using: .utf8)!)
    #expect(hash == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
  }

  @Test("same content produces same hash")
  func sameContentSameHash() {
    let dataA = "test content".data(using: .utf8)!
    let dataB = "test content".data(using: .utf8)!
    #expect(ContentHasher.sha256Hex(of: dataA) == ContentHasher.sha256Hex(of: dataB))
  }

  @Test("different content produces different hash")
  func differentContentDifferentHash() {
    #expect(
      ContentHasher.sha256Hex(of: "hello".data(using: .utf8)!)
        != ContentHasher.sha256Hex(of: "world".data(using: .utf8)!))
  }

  @Test("sha256Hex of file matches sha256Hex of file Data")
  func fileHashMatchesDataHash() throws {
    let tempDir = NSTemporaryDirectory() + "hasher-test-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let filePath = (tempDir as NSString).appendingPathComponent("test.swift")
    let content = "test content"
    try content.write(toFile: filePath, atomically: true, encoding: .utf8)

    let fileHash = try ContentHasher.sha256Hex(of: filePath)
    let dataHash = ContentHasher.sha256Hex(of: content.data(using: .utf8)!)
    #expect(fileHash == dataHash)
  }

  @Test("sha256Hex of non-existent file throws")
  func nonExistentFileThrows() {
    #expect(throws: (any Error).self) {
      try ContentHasher.sha256Hex(of: "/nonexistent/path/file.swift")
    }
  }
}
