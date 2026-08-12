# Phase 3: Incremental Indexing - Research

**Researched:** 2026-08-12
**Domain:** Persistent document-level cache for Swift SCIP indexer (IndexStoreDB → Scip_Document protobuf caching)
**Confidence:** HIGH

## Summary

Phase 3 introduces persistent state to scip-swift for the first time. The current pipeline is stateless — every invocation creates a fresh temp directory (`UUID()`), builds the entire repo from scratch, opens an ephemeral IndexStoreDB, processes every `.swift` file, and writes the `.scip` output. Phase 3 breaks this stateless invariant by caching per-file `Scip_Document` protobuf messages keyed by content hash + version signals, so re-indexing an unchanged repo skips both the build (via persistent scratch path reuse) and the mapping (via cached document reuse).

The technical approach is well-defined because all required APIs are already available in the project's dependencies — no new packages are needed. Content hashing uses `CryptoKit.SHA256` (a macOS system framework, already verified working). Document serialization uses `SwiftProtobuf` (already pinned at 1.38.1). The critical staleness check `IndexStoreDB.dateOfLatestUnitFor(filePath:)` is verified present in the checked-out IndexStoreDB source at `.build/checkouts/indexstore-db/Sources/IndexStoreDB/IndexStoreDB.swift:513-525`. The `IndexStoreDB` initializer already accepts a `databasePath` parameter — persistence is simply a matter of passing a stable path instead of an ephemeral one.

The primary risk is cache correctness: serving stale data silently breaks code intelligence tools. The mitigation strategy is multi-layered: global version invalidation (toolchain + scip-swift + indexstore-db revision), per-file content hash comparison, and `dateOfLatestUnitFor` validation. The external_symbols computation — the only cross-document concern — must always run across the full document set (cached + fresh), because a change in one file can affect which symbols are classified as external.

**Primary recommendation:** Add three new files under `Sources/scip-swift/Caching/` (`CacheStore.swift`, `IndexManifest.swift`, `ContentHasher.swift`), add `--cache-dir` and `--index-only` CLI options, modify `IndexCommand` to use persistent paths when caching is enabled, and modify `SCIPIndexBuilder.build()` to check the cache per file before calling `makeDocument()`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Cache directory management | CLI Layer (`IndexCommand`) | Caching Layer | CLI owns the lifecycle — decides cache-dir path, creates/cleans the directory |
| Document serialization/deserialization | Caching Layer (`CacheStore`) | — | Pure protobuf I/O, no IndexStoreDB dependency |
| Content hashing | Caching Layer (`ContentHasher`) | — | Stateless SHA256 computation via CryptoKit |
| Version signal collection | Platform Layer (`ToolchainInfo`) | Caching Layer | ToolchainInfo already pins `pinnedSwiftVersion`; version constants live in `Version.swift` |
| Stale detection | Caching Layer + Index Access | — | `dateOfLatestUnitFor` is an IndexStoreDB API; content hash is a Caching concern |
| Build path persistence | Build Orchestration (`BuildRunner`) | CLI Layer | Runners accept a scratch/derived-data path; CLI decides if it's ephemeral or persistent |
| Cache integration in mapping loop | SCIP Mapping (`SCIPIndexBuilder`) | Caching Layer | Builder checks cache before `makeDocument()`; external_symbols always recomputed |
| `--index-only` build skip | CLI Layer (`IndexCommand`) | Build Orchestration | CLI decides whether to call `produceIndexStore()` at all |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| CryptoKit | macOS system framework | SHA256 content hashing for cache keys | Apple system framework — zero install, already available on all macOS targets [VERIFIED: runtime test `swift -e 'import CryptoKit'` passed] |
| SwiftProtobuf | 1.38.1 (pinned) | Serialize/deserialize `Scip_Document` to/from disk for cache files | Already in `Package.swift`; `Scip_Document` is `SwiftProtobuf.Message` with `serializedData()` and `init(serializedData:)` [VERIFIED: Package.resolved:34-39] |
| swift-argument-parser | 1.8.2 (pinned) | CLI flag parsing for `--cache-dir` and `--index-only` | Already in use; `@Option` and `@Flag` patterns established [VERIFIED: Package.resolved:18-23] |
| IndexStoreDB | main @ `c993f4fb` (pinned) | `dateOfLatestUnitFor(filePath:)`, `pollForUnitChangesAndWait()`, persistent `databasePath` | Already compiled against; all needed APIs verified present in checked-out source [VERIFIED: Package.resolved:8-12] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Foundation `FileManager` | macOS system | Cache directory creation, file enumeration, path manipulation | Already used throughout codebase for file I/O |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CryptoKit SHA256 | CommonCrypto (`CC_SHA256`) | CryptoKit is the modern Apple-recommended API; CommonCrypto is C-based and deprecated. No reason to use CommonCrypto. |
| Per-file protobuf files | Single JSON manifest with embedded base64 documents | Protobuf binary is more compact and faster than JSON base64; individual files allow atomic per-file updates without rewriting the whole cache |
| Content hash + version key | mtime-based cache | mtime is unreliable across git operations (checkout, pull, reset all change mtime without content change). Content hash is the source of truth. [CITED: .planning/research/STACK.md:255-258] |

**Installation:**
```bash
# No new packages to install. All dependencies are already in Package.swift.
# CryptoKit is a macOS system framework — no Package.swift change needed.
swift build   # rebuilds with existing dependencies
```

**Version verification:** All packages are pinned in `Package.resolved` — no version changes needed for this phase. [VERIFIED: Package.resolved:1-40]

## Package Legitimacy Audit

> This phase installs **zero** new external packages. CryptoKit is a macOS system framework (no SPM dependency). All other libraries (`IndexStoreDB`, `SwiftProtobuf`, `swift-argument-parser`) are already pinned in `Package.resolved` and have been in use since v0.1.0. No legitimacy check is required.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| (none — no new packages) | — | — | — | — | N/A | N/A |

## Architecture Patterns

### System Architecture Diagram

```
                          ┌──────────────────────┐
                          │   CLI (IndexCommand)  │
                          │  --cache-dir <path>   │
                          │  --index-only         │
                          └──────────┬─────────────┘
                                     │
                    ┌────────────────┼────────────────┐
                    │                │                 │
                    ▼                ▼                 ▼
          ┌─────────────────┐ ┌──────────────┐ ┌────────────────┐
          │  --index-only?  │ │ Cache Layer  │ │ Build Orchest. │
          │  YES → skip     │ │ (NEW)        │ │ (existing)     │
          │  build entirely │ │              │ │                │
          └─────────────────┘ │ CacheStore   │ │ SwiftPMRunner  │
                              │ IndexManifest│ │ (persistent    │
                              │ ContentHasher│ │  scratch path) │
                              └──────┬───────┘ └───────┬────────┘
                                     │                 │
                                     │    ┌────────────┘
                                     ▼    ▼
                          ┌──────────────────────┐
                          │   IndexStoreLoader   │
                          │   (persistent        │
                          │    databasePath)     │
                          └──────────┬───────────┘
                                     │
                                     ▼
              ┌───────────────────────────────────────────┐
              │         SCIPIndexBuilder.build()           │
              │                                           │
              │  for each .swift file:                    │
              │    ┌─────────────────────────────────┐    │
              │    │ 1. Compute contentHash (SHA256) │    │
              │    │ 2. dateOfLatestUnitFor(file)?   │    │
              │    │ 3. CacheStore.lookup(hash)?     │    │
              │    │    HIT  → load cached Document  │    │
              │    │    MISS → makeDocument()        │    │
              │    │          → CacheStore.save(doc) │    │
              │    └─────────────────────────────────┘    │
              │                                           │
              │  external_symbols = compute across ALL    │
              │    documents (cached + fresh)             │
              └──────────────────┬────────────────────────┘
                                 │
                                 ▼
                          ┌──────────────┐
                          │  Serialize   │
                          │  → .scip     │
                          │  + manifest  │
                          └──────────────┘
```

**Data flow trace (primary use case: second run on unchanged repo):**
1. `scip-swift <repo>` → `IndexCommand.run()` resolves `cacheDir` (default `<repo>/.scip-cache/`)
2. `IndexManifest` loaded from `<cacheDir>/manifest.json` — checks toolchain/scip-swift/indexstore-db versions
3. Versions match → no global invalidation
4. `SwiftPMBuildRunner` uses persistent scratch path `<cacheDir>/build-scratch/` → `swift build` only recompiles changed files (none changed → near-instant)
5. `IndexStoreDB` opened with persistent `databasePath` = `<cacheDir>/index-db/`
6. For each `.swift` file: compute SHA256 of content → matches manifest hash → `dateOfLatestUnitFor` returns non-nil → load cached `Scip_Document` from `<cacheDir>/docs/<hash>.scipdoc`
7. Recompute `external_symbols` across all documents
8. Serialize final `Scip_Index` → write `.scip` + update manifest

### Recommended Project Structure

```
Sources/scip-swift/
├── Caching/                      # NEW directory — cache layer
│   ├── CacheStore.swift          # Manages cache directory, document I/O
│   ├── IndexManifest.swift        # Codable manifest tracking file hashes + versions
│   └── ContentHasher.swift        # SHA256 utility (CryptoKit wrapper)
├── Commands/
│   └── IndexCommand.swift         # MODIFIED — new --cache-dir, --index-only flags
├── SCIPMapping/
│   └── SCIPIndexBuilder.swift     # MODIFIED — cache integration in build()
├── Build/
│   ├── SwiftPMBuildRunner.swift   # MODIFIED — accept persistent scratch path
│   └── XcodebuildBuildRunner.swift # MODIFIED — accept persistent derived data path
└── (all other existing files unchanged)
```

### Pattern 1: CacheStore — File-Based Document Cache

**What:** A struct that manages the cache directory structure, reads/writes serialized `Scip_Document` protobuf files, and maintains the `IndexManifest`.

**When to use:** When caching is enabled (cache dir exists and is writable). When disabled, `SCIPIndexBuilder` proceeds without caching as before.

**Example:**
```swift
// Sources/scip-swift/Caching/CacheStore.swift

import Foundation
import SwiftProtobuf

struct CacheStore {
  let cacheDir: String

  private var docsDir: String { "\(cacheDir)/docs" }
  private var manifestPath: String { "\(cacheDir)/manifest.json" }

  // Global version check — if any version differs, delete entire cache
  func loadManifest() throws -> IndexManifest? {
    guard FileManager.default.fileExists(atPath: manifestPath) else { return nil }
    let data = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
    return try JSONDecoder().decode(IndexManifest.self, from: data)
  }

  func saveManifest(_ manifest: IndexManifest) throws {
    try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(manifest)
    try data.write(to: URL(fileURLWithPath: manifestPath))
  }

  func loadDocument(hash: String) -> Scip_Document? {
    let path = "\(docsDir)/\(hash).scipdoc"
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
    return try? Scip_Document(serializedData: data)
  }

  func saveDocument(_ document: Scip_Document, hash: String) throws {
    try FileManager.default.createDirectory(atPath: docsDir, withIntermediateDirectories: true)
    let data = document.serializedData()
    try data.write(to: URL(fileURLWithPath: "\(docsDir)/\(hash).scipdoc"))
  }

  func invalidateAll() throws {
    try? FileManager.default.removeItem(atPath: cacheDir)
  }
}
```

### Pattern 2: IndexManifest — Codable Version Tracking

**What:** A `Codable` struct that stores global version signals and per-file cache entries. This is the cache invalidation oracle.

**Example:**
```swift
// Sources/scip-swift/Caching/IndexManifest.swift

import Foundation

struct IndexManifest: Codable {
  var toolchainVersion: String      // ToolchainInfo.pinnedSwiftVersion
  var converterVersion: String      // ScipSwiftVersion.version
  var indexstoreDbRevision: String   // from Package.resolved
  var buildToolName: String          // "swiftpm" or "xcodebuild"
  var files: [String: FileEntry]     // relativePath → entry

  struct FileEntry: Codable {
    var contentHash: String          // SHA256 hex of file content
    var cachedAt: Date               // when this entry was cached
  }

  func isCompatibleWith(
    toolchainVersion: String,
    converterVersion: String,
    indexstoreDbRevision: String,
    buildToolName: String
  ) -> Bool {
    self.toolchainVersion == toolchainVersion
      && self.converterVersion == converterVersion
      && self.indexstoreDbRevision == indexstoreDbRevision
      && self.buildToolName == buildToolName
  }
}
```

### Pattern 3: ContentHasher — SHA256 via CryptoKit

**What:** Stateless `enum` wrapper around `CryptoKit.SHA256` following the project's `enum`-as-namespace convention for stateless utilities.

**Example:**
```swift
// Sources/scip-swift/Caching/ContentHasher.swift

import Foundation
import CryptoKit

enum ContentHasher {
  static func sha256Hex(of filePath: String) throws -> String {
    let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
  }

  static func sha256Hex(of data: Data) -> String {
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
  }
}
```

### Pattern 4: Cache Integration in SCIPIndexBuilder

**What:** Modify `build()` to check the cache before calling `makeDocument()`. The pure mappers (`SCIPSymbolFormatter`, `SymbolKindMapping`, `SymbolRoleMapping`, `PositionMapping`, `RelationshipMapping`, `SignatureMapping`) are not touched — they remain stateless pure functions.

**Key invariant:** `makeDocument()` remains a private method with the same signature. The cache layer wraps it — it does not modify the mapping logic. If caching is disabled (no `cacheStore`), the behavior is identical to the current code.

**Example (conceptual — the planner should use this structure):**
```swift
// In SCIPIndexBuilder — modified build() method

func build() throws -> Scip_Index {
  let indexStoreDB = try IndexStoreLoader.open(storePath: indexStorePath, databasePath: databasePath)

  // After opening, poll for any unit changes if the store was updated
  indexStoreDB.pollForUnitChangesAndWait()

  var index = Scip_Index()
  index.metadata = makeMetadata()

  var referencedSymbols: [String: Scip_SymbolInformation] = [:]
  var systemReferencedSymbols: [String: Scip_SymbolInformation] = [:]
  var definedSymbolStrings: Set<String> = []

  for filePath in SwiftFileDiscovery.swiftFiles(underRepoPath: repoPath) {
    let document: Scip_Document?

    if let cacheStore,
       let contentHash = try? ContentHasher.sha256Hex(of: filePath),
       cacheStore.loadDocument(hash: contentHash) != nil,
       indexStoreDB.dateOfLatestUnitFor(filePath: filePath) != nil {
      // CACHE HIT: content unchanged + file is indexed
      document = cacheStore.loadDocument(hash: contentHash)
    } else {
      // CACHE MISS: reprocess via makeDocument()
      document = makeDocument(
        filePath: filePath,
        indexStoreDB: indexStoreDB,
        referencedSymbols: &referencedSymbols,
        systemReferencedSymbols: &systemReferencedSymbols
      )
      // Cache the fresh document
      if let cacheStore, let doc = document,
         let contentHash = try? ContentHasher.sha256Hex(of: filePath) {
        try? cacheStore.saveDocument(doc, hash: contentHash)
      }
    }

    if let document {
      definedSymbolStrings.formUnion(document.symbols.map(\.symbol))
      index.documents.append(document)
    }
  }

  // external_symbols MUST be recomputed across ALL documents every time
  index.externalSymbols = Array(systemReferencedSymbols.values) + Array(referencedSymbols.values)
    .filter { !definedSymbolStrings.contains($0.symbol) }
    .sorted { $0.symbol < $1.symbol }

  return index
}
```

**⚠️ Critical subtlety:** When loading a cached document, the referenced/system symbols from that document are NOT available for the `external_symbols` computation (they were tracked in `referencedSymbols` during `makeDocument()`, but loading from cache skips that). The planner must address this — see [Open Questions](#open-questions) below. The recommended approach is to extract the referenced symbol data from the cached document's occurrences and symbols directly, or to always recompute `external_symbols` by scanning all documents' occurrences after assembly.

### Anti-Patterns to Avoid

- **Caching the entire `Scip_Index`:** A single file change invalidates the entire cache — no benefit over full reindex. Cache per-document instead.
- **Caching the `IndexStoreDB` instance across CLI invocations:** scip-swift is a one-shot CLI, not a daemon. Open IndexStoreDB fresh each run (cheap, ~seconds) with `waitUntilDoneInitializing: true`. Cache the `databasePath` on disk, not the database connection.
- **mtime-based cache keys:** Git operations (checkout, pull, reset) change mtime without changing content. Content hash (SHA256) is the source of truth.
- **Skipping `external_symbols` recomputation:** This is the ONLY cross-document concern. It must run across all documents (cached + fresh) every time, because a definition added in one file can turn a previously-external symbol into a defined one.
- **Modifying the pure mappers for caching:** The cache layer wraps `makeDocument()`; the mappers inside (`SCIPSymbolFormatter`, `SymbolKindMapping`, etc.) must remain pure and untouched.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Content hashing | Custom hash function | `CryptoKit.SHA256` | SHA256 is cryptographically standard, collision-resistant, and Apple-provided. Building a hash is a waste and introduces correctness risk. |
| Protobuf serialization | Custom binary format for cached documents | `Scip_Document.serializedData()` / `Scip_Document(serializedData:)` | SwiftProtobuf already provides this — `Scip_Document` conforms to `SwiftProtobuf.Message`. |
| JSON manifest serialization | Custom manifest format | `Codable` + `JSONEncoder`/`JSONDecoder` | Foundation's `Codable` is the standard Swift serialization mechanism. The manifest is a simple struct. |
| Incremental build logic | Custom file-change detection for the compiler | `swift build --scratch-path` / `xcodebuild -derivedDataPath` | The build tools already implement incremental compilation. Just reuse their scratch path. |
| IndexStore staleness detection | Custom timestamp comparison logic | `IndexStoreDB.dateOfLatestUnitFor(filePath:)` | The API is purpose-built for this exact use case (verified at IndexStoreDB.swift:513-525). |

**Key insight:** Every piece of infrastructure needed for this phase already exists — CryptoKit for hashing, SwiftProtobuf for serialization, IndexStoreDB for staleness, SwiftPM/Xcodebuild for incremental builds. The work is integration and orchestration, not building new subsystems.

## Runtime State Inventory

> This phase introduces persistent state for the first time. The categories below document what new runtime state is created.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | NEW: `<cacheDir>/manifest.json` (per-file hashes + version metadata); NEW: `<cacheDir>/docs/<hash>.scipdoc` (serialized `Scip_Document` protobufs) | Created on first cached run; updated on subsequent runs. Must be `.gitignore`d. |
| Live service config | None — scip-swift is a one-shot CLI, no running services | None |
| OS-registered state | None — no launchd/cron/pm2 registrations | None |
| Secrets/env vars | None — no secrets in cache (version strings and hashes only) | None |
| Build artifacts | NEW: `<cacheDir>/build-scratch/` (SwiftPM incremental build output); NEW: `<cacheDir>/index-db/` (IndexStoreDB database). These replace the ephemeral `$TMPDIR/scip-swift-<uuid>/` directory | Must be `.gitignore`d. Old artifacts accumulate — see GC strategy below. |

**GC strategy for old build artifacts:** The cache directory's `docs/` folder accumulates `.scipdoc` files for old file contents (hashes change when files are edited). A simple cleanup pass: after writing the new manifest, delete any `.scipdoc` file whose hash is not in the current manifest. This is cheap (directory listing + set difference).

## Common Pitfalls

### Pitfall 1: Stale Cache Serves Bad Data

**What goes wrong:** A cached `Scip_Document` is reused even though the source file changed or the toolchain was upgraded. Result: occurrence line numbers drift, symbols point to old locations, `scip lint` passes but Sourcegraph shows incorrect navigation.

**Why it happens:** Content hash doesn't match but cache lookup succeeds due to a bug in the hash computation (e.g., reading the file after it was modified during the build). Or: toolchain version changes but the manifest's global version check is skipped.

**How to avoid:** Three-layer invalidation: (1) global version check in manifest on load — toolchain, scip-swift, indexstore-db revision; (2) per-file content hash (SHA256 of file content on disk); (3) `dateOfLatestUnitFor(filePath:)` returns non-nil (file exists in current indexstore).

**Warning signs:** Integration test fails when run twice in sequence; occurrence line numbers don't match source after a rename; `scip lint` passes but navigation jumps to wrong locations.

### Pitfall 2: external_symbols Computed Incorrectly with Cached Documents

**What goes wrong:** When a document is loaded from cache, the `referencedSymbols` / `systemReferencedSymbols` dictionaries (which track referenced-but-undefined symbols for `external_symbols`) are not populated — those are only updated inside `makeDocument()`. The final `external_symbols` list is incomplete, causing `scip lint` errors (unresolved symbol references).

**Why it happens:** The cache stores the `Scip_Document` protobuf, not the intermediate `referencedSymbols` dictionary. The external_symbols computation depends on tracking all referenced symbols across ALL documents.

**How to avoid:** After assembling all documents (cached + fresh), re-scan each document's occurrences to build the referenced-symbols set. Or: store the referenced-symbols data alongside the cached document. The simpler approach is post-assembly scanning: iterate all `document.occurrences`, extract `scipOccurrence.symbol` strings that don't appear in any document's `document.symbols` set.

**Warning signs:** `scip lint` error: symbol referenced in occurrences but not in `external_symbols` or `documents[].symbols`.

### Pitfall 3: Partial Build Produces Incomplete IndexStore

**What goes wrong:** An incremental build fails partway through (compilation error in one file). The IndexStore exists but is incomplete — some files' units are missing or stale. The exit-code check passes if the build "succeeds" but the index is still wrong.

**Why it happens:** `swift build --scratch-path` may report success even if some files weren't recompiled (if the scratch path is in a bad state from an interrupted previous build).

**How to avoid:** Always check `result.exitCode == 0` (already done in `SwiftPMBuildRunner.produceIndexStore()` — preserve this). Additionally, after opening IndexStoreDB, call `pollForUnitChangesAndWait()` to ensure the database reflects the current store state. If a file has no occurrences and `dateOfLatestUnitFor` returns `nil`, skip it (it wasn't indexed).

**Warning signs:** Documents missing from output; `dateOfLatestUnitFor` returns `nil` for files that exist on disk.

### Pitfall 4: --index-only Mode with Missing/Stale IndexStore

**What goes wrong:** User runs `scip-swift <repo> --index-only` but the IndexStore doesn't exist (first run, or cache was deleted). The tool either crashes or produces an empty index silently.

**Why it happens:** `--index-only` skips the build step entirely. If there's no IndexStore at the expected path, `IndexStoreLoader.open()` will fail, or the IndexStoreDB will be empty.

**How to avoid:** Validate that the IndexStore exists before skipping the build. If `--index-only` is passed and the IndexStore path doesn't exist, print a clear error message: "No IndexStore found at <path>. Run without --index-only first to build the index."

**Warning signs:** Empty `.scip` output; `IndexStoreDB` opens but `symbolOccurrences` returns empty for every file.

### Pitfall 5: Cache Directory in .git or Committed Accidentally

**What goes wrong:** The `.scip-cache/` directory is accidentally committed to the repo, bloating the repository with binary cache files and index databases.

**Why it happens:** The default cache path is `<repo>/.scip-cache/`, which is inside the repo tree. If `.gitignore` isn't updated, the cache gets committed.

**How to avoid:** Add `.scip-cache/` to `.gitignore` as part of this phase. The integration test must clean up its cache directory after running.

**Warning signs:** `git status` shows `.scip-cache/` files; repository size grows unexpectedly.

## Code Examples

### CLI Flag Addition (ArgumentParser)

```swift
// In IndexCommand.swift — follows existing @Option/@Flag patterns exactly

@Option(
  name: .long,
  help: "Directory for the incremental index cache. Defaults to <repo>/.scip-cache/."
)
var cacheDir: String?

@Flag(
  name: .long,
  help: "Skip the build step and read an existing IndexStore directly."
)
var indexOnly: Bool = false
```

[VERIFIED: existing pattern at IndexCommand.swift:14-24 — `@Option(name: .long)` and `@Flag` are the established convention]

### Persistent Database Path

```swift
// In IndexCommand.run() — change from ephemeral to persistent when caching is enabled

let resolvedCacheDir = cacheDir
  ?? (resolvedRepoPath as NSString).appendingPathComponent(".scip-cache")

let databasePath: String
if indexOnly || cacheDir != nil {
  // Persistent: reuse across runs
  databasePath = (resolvedCacheDir as NSString).appendingPathComponent("index-db")
} else {
  // Ephemeral: current behavior (backward compatible)
  databasePath = (workDirectory as NSString).appendingPathComponent("index-db")
}
```

### Persistent Build Scratch Path

```swift
// In IndexCommand.produceIndexStore() — use persistent scratch when caching is enabled

case .swiftpm:
  let scratchPath: String
  if persistentCache {
    scratchPath = (cacheDir as NSString).appendingPathComponent("build-scratch")
  } else {
    scratchPath = (workDirectory as NSString).appendingPathComponent("scratch")
  }
  let runner = SwiftPMBuildRunner(
    repoPath: repoPath,
    configuration: configuration,
    scratchPath: scratchPath
  )
  return try runner.produceIndexStore()
```

[VERIFIED: SwiftPMBuildRunner already accepts `scratchPath` as a constructor parameter — no runner change needed, only the caller decides the path value. SwiftPMBuildRunner.swift:14-16]

### --index-only Validation

```swift
// In IndexCommand.run() — validate IndexStore exists before skipping build

if indexOnly {
  let persistentIndexStorePath = (resolvedCacheDir as NSString).appendingPathComponent("build-scratch")
  // The actual index store path is under <scratch>/<triple>/<config>/index/store
  // We need to find it — reuse SwiftPMBuildRunner.findIndexStore
  guard let indexStorePath = SwiftPMBuildRunner.findIndexStore(
    underScratchPath: persistentIndexStorePath,
    configuration: configuration
  ) else {
    throw BuildError.indexStoreNotProduced(
      expectedPath: "\(persistentIndexStorePath)/<triple>/\(configuration.rawValue)/index/store"
    )
  }
  // Skip produceIndexStore(), go directly to SCIPIndexBuilder
  buildResult = IndexStoreBuildResult(indexStorePath: indexStorePath)
} else {
  buildResult = try produceIndexStore(...)
}
```

**⚠️ Note:** `SwiftPMBuildRunner.findIndexStore` is currently `private static`. It needs to be made accessible (either `internal` or moved to a shared location) for `--index-only` mode. The planner should consider extracting it to a standalone utility or making it `internal`.

### dateOfLatestUnitFor Usage

```swift
// Verified API signature from IndexStoreDB.swift:513-525:
// public func dateOfLatestUnitFor(filePath: String) -> Date?
// Returns nil if no unit containing the file exists.
// Returns the timestamp (nanoseconds since epoch → Date) of the latest unit.

// Usage in cache validation:
if let unitDate = indexStoreDB.dateOfLatestUnitFor(filePath: filePath) {
  // File is indexed in the current store — safe to check cache
} else {
  // File not in indexstore — can't use cache, must process (or skip if no occurrences)
}
```

[VERIFIED: `.build/checkouts/indexstore-db/Sources/IndexStoreDB/IndexStoreDB.swift:513-525` — `dateOfLatestUnitFor(filePath:)` returns `Date?`, nil when no unit exists]

### pollForUnitChangesAndWait Usage

```swift
// Verified API from IndexStoreDB.swift:158-162:
// public func pollForUnitChangesAndWait(isInitialScan: Bool = false)
// Scans all unit files on disk and registers changes. Costly but ensures DB is current.

// Usage after opening IndexStoreDB with a persistent store that may have been updated:
let indexStoreDB = try IndexStoreLoader.open(storePath: storePath, databasePath: dbPath)
indexStoreDB.pollForUnitChangesAndWait()
```

[VERIFIED: `.build/checkouts/indexstore-db/Sources/IndexStoreDB/IndexStoreDB.swift:158-162`]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Ephemeral temp dir per run (`UUID()`) | Persistent cache dir (`<repo>/.scip-cache/`) | Phase 3 | Build artifacts and index DB persist across runs, enabling incremental builds |
| Fresh IndexStoreDB each run | Persistent databasePath with `pollForUnitChangesAndWait()` | Phase 3 | Database initialization cost amortized; only changed units need processing |
| Full reprocessing of every file | Per-file cache with content hash check | Phase 3 | Unchanged files skip `makeDocument()` entirely — O(1) vs O(occurrences) |

**Not deprecated/outdated:** The pure-function mapper pattern, `enum`-as-namespace convention, and exhaustive switch safety net all remain unchanged. The cache layer is additive — it wraps the existing pipeline, it doesn't replace any mapper.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `SwiftPMBuildRunner.findIndexStore` can be made `internal` for `--index-only` reuse | Code Examples | Low — if it can't be shared, a duplicate utility is trivial to write |
| A2 | `Scip_Document` round-trips cleanly through `serializedData()` / `init(serializedData:)` | Pattern 1 | Low — SwiftProtobuf guarantees this for all `Message` conformers; `Scip_Document` is auto-generated |
| A3 | `external_symbols` can be recomputed by scanning cached documents' occurrences post-assembly | Pitfall 2 | Medium — if occurrences don't contain enough info to distinguish referenced vs. defined, the external_symbols computation needs to be redesigned. Mitigation: occurrences with role `.definition` → defined; others → referenced. The symbol string distinguishes local from global. |
| A4 | The `Package.resolved` indexstore-db revision string can be read at runtime for the cache key | Pattern 2 | Low — it can be read from the file, or the `IndexStoreLibrary.version` runtime API can be used instead (verified at IndexStoreDB.swift:548-556) |
| A5 | `.scip-cache/` is the right default cache directory name | CLI Flag | Low — easily changed; follows the convention of dot-prefixed tool directories (`.build`, `.swiftpm`, `.git`) |

## Open Questions (RESOLVED)

1. **external_symbols computation with cached documents**
   - What we know: `makeDocument()` populates `referencedSymbols` and `systemReferencedSymbols` as side-effects during the occurrence loop. These are used for `external_symbols`. When a document is loaded from cache, these dictionaries are not populated.
   - What's unclear: Whether scanning the cached document's `occurrences` and `symbols` arrays post-assembly provides enough information to reconstruct the `external_symbols` set correctly.
   - RESOLVED: Plan 03-02 Task 1 implements post-assembly occurrence scanning. The isSystem distinction is not preserved through cache (Scip_Occurrence protobuf has no isSystem field); referenced-but-undefined heuristic is used for cached documents with documented rationale. (cached + fresh), iterate all documents' occurrences. An occurrence's `symbol` that doesn't appear in any document's `symbols[].symbol` is external. Check `isSystem` — but `isSystem` is an IndexStoreDB `SymbolLocation` property, not preserved in the SCIP `Scip_Occurrence` protobuf. **The planner must decide whether to store `isSystem` info in the cached document, or accept that `external_symbols` for cached documents uses the referenced-but-undefined heuristic.** Given that Phase 1 (META-04) moved to `isSystem`-based classification, the cache should preserve this info — potentially by storing the external symbol classification in the document itself or in a sidecar.

2. **Xcode `--index-only` path resolution**
   - What we know: SwiftPM stores the index store under `<scratch>/<triple>/<config>/index/store`. Xcode stores it under `<derivedData>/Index.noindex/DataStore`.
   - What's unclear: Whether the `--index-only` mode should support both build backends or just SwiftPM initially. The `findIndexStore` logic is SwiftPM-specific.
   - RESOLVED: SwiftPM-only for initial implementation (Plan 03-02 Task 2). Xcode --index-only deferred — documented as a known limitation. SwiftPM is the primary use case; Xcode path uses a different index store location convention that requires separate resolution logic. XcodeBuildRunner already knows the index store path (`<derivedDataPath>/Index.noindex/DataStore`), so validation is straightforward.

3. **Cache directory in multi-module repos**
   - What we know: The default cache dir is `<repo>/.scip-cache/`. For a repo with multiple Swift packages (monorepo), all modules share one cache.
   - What's unclear: Whether file path collisions across modules could cause cache issues. Since the cache is keyed by content hash (not file path), this shouldn't be a problem — different files produce different hashes.
   - RESOLVED: No action needed. Content hash is the primary key; file path collisions across modules are not possible because different files produce different hashes.; file path is only for manifest tracking. No action needed.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| CryptoKit | ContentHasher (SHA256 hashing) | ✓ | macOS system framework | — |
| SwiftProtobuf | CacheStore (document serialization) | ✓ | 1.38.1 | — |
| IndexStoreDB | Stale detection (`dateOfLatestUnitFor`) | ✓ | main @ `c993f4fb` | — |
| swift-argument-parser | CLI flags (`--cache-dir`, `--index-only`) | ✓ | 1.8.2 | — |
| `swift build --scratch-path` | Incremental SwiftPM builds | ✓ | Swift 6.2.4 | — |
| `xcodebuild -derivedDataPath` | Incremental Xcode builds | ✓ | Xcode (any recent) | — |

**Missing dependencies with no fallback:** None — all required tools and frameworks are available.

**Missing dependencies with fallback:** None needed.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (`@Suite`/`@Test` with `#expect`) |
| Config file | None — tests are in `Tests/scip-swiftTests/`, run via `swift test` |
| Quick run command | `swift test --filter ContentHasherTests` |
| Full suite command | `swift test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INCR-01 | Persistent IndexStoreDB database path | unit | `swift test --filter CacheStoreTests` | ❌ Wave 0 |
| INCR-02 | `--cache-dir` CLI option | unit | `swift test --filter IndexCommandCacheTests` | ❌ Wave 0 |
| INCR-03 | Per-file document cache with content hash | unit | `swift test --filter CacheStoreTests` | ❌ Wave 0 |
| INCR-04 | Stale detection via `dateOfLatestUnitFor` + hash | unit | `swift test --filter ContentHasherTests` | ❌ Wave 0 |
| INCR-05 | `--index-only` mode skips build | integration | `swift test --filter IncrementalIntegrationTests` | ❌ Wave 0 |
| INCR-06 | Cache invalidation on version change | unit | `swift test --filter IndexManifestTests` | ❌ Wave 0 |
| TEST-04 | Integration test: index → modify → re-index → verify cache correctness | integration | `swift test --filter IncrementalIntegrationTests` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `swift test --filter <relevant test suite>`
- **Per wave merge:** `swift test`
- **Phase gate:** Full suite green + integration test confirms cache correctness (index → modify → re-index → changed symbols updated, unchanged symbols preserved, `scip lint` passes)

### Wave 0 Gaps

- [ ] `Tests/scip-swiftTests/ContentHasherTests.swift` — covers INCR-03 (SHA256 hashing correctness)
- [ ] `Tests/scip-swiftTests/IndexManifestTests.swift` — covers INCR-06 (version compatibility check, Codable round-trip)
- [ ] `Tests/scip-swiftTests/CacheStoreTests.swift` — covers INCR-01, INCR-03 (document save/load, manifest round-trip, cache invalidation)
- [ ] `Tests/scip-swiftTests/IncrementalIntegrationTests.swift` — covers INCR-05, TEST-04 (end-to-end: build → index → modify file → re-index → verify cache hit/miss + scip lint)

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | N/A — CLI tool, no authentication |
| V3 Session Management | no | N/A — one-shot CLI, no sessions |
| V4 Access Control | no | N/A — no privileged operations |
| V5 Input Validation | yes | File path validation — `--cache-dir` and `--index-only` accept user-provided paths; must validate the path is writable and doesn't escape to sensitive locations (symlink attacks) |
| V6 Cryptography | yes | SHA256 via CryptoKit (Apple-provided, FIPS-validated) — never hand-roll hashing |
| V7 Error Handling | yes | `BuildError` pattern — cache errors should follow the exhaustive enum convention |
| V8 Data Protection | yes | Cache directory must not store secrets; the cache contains only version strings, file hashes, and SCIP protobuf data |

### Known Threat Patterns for Swift CLI Caching

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Symlink attack on cache directory | Tampering | Validate `cacheDir` is not a symlink to a sensitive location; `FileManager.fileExists(isDirectory:)` check |
| Path traversal via `--cache-dir` | Tampering | Resolve to absolute path via `URL(fileURLWithPath:).standardizedFileURL.path` (already done for `repoPath`) |
| Cache poisoning (malicious `.scipdoc` injection) | Tampering | Content hash filenames are derived from SHA256 of source — an attacker would need to match the hash, which is computationally infeasible |
| Sensitive file content in cache | Information Disclosure | Cache stores source file hashes (not content) and SCIP protobufs (which contain symbol names/locations, not arbitrary source). Document this in `.gitignore` advisory. |

## Sources

### Primary (HIGH confidence)

- **`.build/checkouts/indexstore-db/Sources/IndexStoreDB/IndexStoreDB.swift`** — Verified: `dateOfLatestUnitFor(filePath:) -> Date?` (lines 513-525), `pollForUnitChangesAndWait(isInitialScan:)` (lines 158-162), `IndexStoreDB` initializer with `databasePath`/`storePath`/`waitUntilDoneInitializing`/`listenToUnitEvents` parameters (lines 77-90), `IndexStoreLibrary.version` (lines 548-556)
- **`.build/checkouts/indexstore-db/Sources/IndexStoreDB/IndexDelegate.swift`** — Verified: `IndexDelegate` protocol with `unitIsOutOfDate` callback (lines 20-50) — available but not needed for CLI mode
- **`.build/checkouts/indexstore-db/Sources/IndexStoreDB/SymbolLocation.swift`** — Verified: `isSystem: Bool` field (line 23), `timestamp: Date` field (line 19)
- **`.build/checkouts/indexstore-db/Sources/IndexStoreDB/SymbolOccurrence.swift`** — Verified: `relations: [SymbolRelation]` array (line 19)
- **`.build/checkouts/indexstore-db/Sources/IndexStoreDB/SymbolRole.swift`** — Verified: all 10 relation roles (lines 31-40)
- **`Sources/scip-swift/Commands/IndexCommand.swift`** — Ground truth: current pipeline structure (lines 1-82), temp directory creation via `UUID()` (line 77), ephemeral database path (line 36)
- **`Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift`** — Ground truth: `build()` method (lines 17-48), `makeDocument()` (lines 62-148), external_symbols computation (lines 41-43)
- **`Sources/scip-swift/Build/SwiftPMBuildRunner.swift`** — Ground truth: `scratchPath` constructor param (line 14), `findIndexStore` private static (lines 38-49)
- **`Sources/scip-swift/Build/XcodebuildBuildRunner.swift`** — Ground truth: `derivedDataPath` constructor param (line 13), index store path convention (lines 53-54)
- **`Sources/scip-swift/Platform/ToolchainInfo.swift`** — Verified: `pinnedSwiftVersion = "6.2.4"` (line 8)
- **`Sources/scip-swift/Version.swift`** — Verified: `version = "0.1.2"` (line 6)
- **`Package.resolved`** — Verified: indexstore-db revision `c993f4fb4f321fae1945e96a2377742f24e132f4` (line 11)
- **CryptoKit runtime test** — Verified: `swift -e 'import CryptoKit; ...'` produces correct SHA256 hash

### Secondary (MEDIUM confidence)

- **`.planning/research/STACK.md`** — Prior research on cache layering design (two-layer cache: IndexStoreDB-persistent + document-level), cache invalidation triggers
- **`.planning/research/ARCHITECTURE.md`** — Prior research on pipeline restructuring, cache flow diagram, component responsibilities
- **`.planning/research/PITFALLS.md`** — Pitfall 3 (stale incremental cache), USR instability across toolchains

### Tertiary (LOW confidence)

- None — all findings in this research are verified against source code or runtime tests

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs verified by reading checked-out IndexStoreDB source + Package.resolved + runtime CryptoKit test
- Architecture: HIGH — every file to be modified has been read; the integration points are clear
- Pitfalls: HIGH — grounded in actual codebase structure and verified IndexStoreDB API semantics
- Cache correctness: MEDIUM — the external_symbols recomputation with cached documents has one open design question (see Open Questions #1)

**Research date:** 2026-08-12
**Valid until:** 2026-09-12 (30 days — stable codebase, no external API changes expected)
