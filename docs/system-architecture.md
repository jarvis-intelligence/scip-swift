<!-- generated-by: gsd-doc-writer -->
# scip-swift: System Architecture

## Overview

`scip-swift` is a command-line tool that transforms a Swift repository's compiler index (IndexStore) into a standard SCIP protobuf output. The pipeline consists of four major phases: build, index discovery, SCIP mapping, and serialization.

## Architecture Diagram

![scip-swift system architecture](./diagrams/system-architecture.png)

The diagram is organized as six layers, matching the sections below:

| Layer | Contents |
|---|---|
| 1 · CLI | `ScipSwiftCommand` — flag parsing, pipeline coordination, output write |
| 2 · Build orchestration | `BuildBackendDetector` fanning out to `SwiftPMBuildRunner` / `XcodebuildBuildRunner` (both via `SubprocessRunner`) |
| 3 · Index access | `IndexStoreLoader` (opens IndexStoreDB) and `SwiftFileDiscovery` (walks the repo) |
| 4 · SCIP mapping | `SCIPIndexBuilder` driving four pure mappers: symbol string, kind, role, position |
| 5 · Serialization & output | Generated `Scip.pb.swift` → `index.scip` |
| 6 · Consumers | `scip` CLI, Sourcegraph, SCIP-aware editor plugins |

Colour coding: blue = user-facing boundary, purple = process/orchestration, yellow = I/O against
the compiler index, orange = pure mapping functions (no I/O), green = emitted artifact.

**Source**: [`diagrams/system-architecture.excalidraw`](./diagrams/system-architecture.excalidraw) — edit at
[excalidraw.com](https://excalidraw.com) and re-export the PNG alongside it.

## Core Components

### 1. CLI Layer (`ScipSwiftCommand.swift` → `Commands/IndexCommand.swift`)

**Responsibility**: Parse user arguments, coordinate the pipeline, handle top-level errors.

**Inputs**:
- Positional: `repoPath` (target repository)
- Options: `--output`, `--build-tool`, `--configuration`, `--scheme`, `--version`

**Outputs**:
- `.scip` file (serialized protobuf Index) or error message

**Key logic**:
- Normalizes input paths (repo path defaults to the current working directory; no pre-flight repo-existence or output-writability checks are performed)
- Invokes `BuildBackendDetector` to choose build runner
- Calls `BuildRunner.produceIndexStore()` to get IndexStore path
- Delegates to `SCIPIndexBuilder` for conversion
- Handles serialization and file I/O
`ScipSwiftCommand` is the `@main` root; `index` is its `defaultSubcommand` (alongside the `index-many` subcommand), so the bare `scip-swift <repo>` form dispatches to `IndexCommand`, which owns the temporary work directory and coordinates the whole pipeline.

### 2. Build System Abstraction

**Responsibility**: Detect the appropriate build tool and execute it with indexing enabled.

#### BuildBackendDetector

- Checks for `Package.swift` (SwiftPM) or `.xcworkspace`/`.xcodeproj` (Xcode).
- Prefers `.xcworkspace` over `.xcodeproj`.
- Returns a `BuildTool` enum indicating which runner to use.

#### BuildRunner Protocol

```swift
protocol BuildRunner {
  func produceIndexStore() throws -> IndexStoreBuildResult
}
```

Implementations:

**SwiftPMBuildRunner**:
- Runs: `swift build --configuration <c> --scratch-path <path> --enable-index-store`
- Locates IndexStore: `<scratch-path>/<triple>/<configuration>/index/store`
- The scratch path lives under `IndexCommand`'s per-run temp directory (`$TMPDIR/scip-swift-<uuid>/scratch`), created fresh each invocation.

**XcodebuildBuildRunner**:
- Resolves `.xcworkspace` or `.xcodeproj` path
- Auto-detects scheme if exactly one exists; otherwise requires `--scheme`
- Runs: `xcodebuild -workspace <p> -scheme <s> -derivedDataPath <p> COMPILER_INDEX_STORE_ENABLE=YES build`
- Locates IndexStore: `<derivedDataPath>/Index.noindex/DataStore`

**Error Handling** (`BuildError` enum):
- `cannotDetectBuildSystem` — Neither Package.swift nor Xcode project found
- `xcodebuildSchemeRequired` — Multiple schemes, user must specify via `--scheme`
- `toolNotLaunchable` — Build tool executable not found on PATH
- `buildFailed` — Build command exited with non-zero status
- `indexStoreNotProduced` — Build succeeded but IndexStore not found at expected location

### 3. Index Discovery

**Responsibility**: Load the IndexStore and discover Swift source files.

#### IndexStoreLoader

- Uses `IndexStoreDB` to open the IndexStore database at the path returned by the build runner.
- Locates `libIndexStore.dylib` via `xcrun --find swift` (uses the active Xcode toolchain).
- Provides query interface for symbol occurrences.

#### SwiftFileDiscovery

- Walks the repository for `.swift` files.
- Skips common build/cache directories: `.build`, `.git`, `.swiftpm`, `DerivedData`, `Pods`, `.index-build`.
- Returns a list of source file paths to be indexed.

### 4. SCIP Conversion Pipeline (`SCIPIndexBuilder`)

**Responsibility**: Query IndexStore and convert results to SCIP protobuf messages.

**Main loop**:

```
for each Swift file in repo:
  for each symbol occurrence in IndexStore for that file:
    create Scip_Occurrence:
      - range: convert 1-based point to 0-based range
      - symbol: format USR as SCIP symbol string
    create Scip_SymbolInformation:
      - kind: map IndexStoreDB kind to SCIP kind
      - roles: map IndexStoreDB role bits to SCIP role bits
    add to file's Scip_Document.occurrences

    track defined/referenced symbols for external_symbols
  
  sort occurrences by range
  create Scip_Document for file
  add to Scip_Index.documents

populate Scip_Index.external_symbols with:
  - referenced-but-undefined symbols (SCIP requirement)
  - symbol kind and docstring metadata
```

**Key Modules**:

**SCIPSymbolFormatter**:
- Converts IndexStoreDB's raw compiler USR (Unified Symbol Resolution string) to SCIP canonical format.
- Keeps USR opaque (no demangling); represents as a single escaped descriptor.
- Assigns `.local` IDs to locally-scoped symbols using `LocalSymbolNumberer`.
- Example: `_$s5Hello7GreeterC7sayHelloyySSF` → `scip-swift swift scip-swift/[...]/scip-swift/...` (actual formatting depends on USR structure)

**SymbolKindMapping**:
- Maps `IndexStoreDB.Symbol.Kind` enum to `Scip_SymbolInformation.Kind` enum.
- Exhaustive switch ensures all Swift symbol kinds are mapped.
- Some kinds (e.g., destructor, conversion function) map to closest SCIP equivalent (e.g., `.method`).

**SymbolRoleMapping**:
- Maps `IndexStoreDB.SymbolRole` bits (definition, reference, read, write, call, etc.) to SCIP `SymbolRole` bits.
- Important: SCIP's SymbolRole has no call-specific bit; call sites are marked as references.
- Returns a packed `Int32` bitfield (`scipRoles(for:)`). `definition` sets the `Definition` bit; `.write` sets `WriteAccess`; otherwise `.reference`/`.read` set `ReadAccess`. `write` is mutually exclusive with `read`, and `.call` contributes no dedicated bit (none exists in `scip.proto`), riding along on `.reference`.

**PositionMapping**:
- IndexStoreDB provides a single anchor point: 1-based line and UTF8 column.
- SCIP expects 0-based half-open range (start and end points).
- End column is approximated from the symbol's display-name length.
- Example: if symbol "greet" starts at line 5, column 10, end is estimated at column 15.
- **Limitation**: Not exact for compound names like `greet(name:)` or unusual spellings; see [README.md](../README.md) for details.

### 5. Protobuf Serialization

**Responsibility**: Serialize the built `Scip_Index` to a binary protobuf file.

- Uses `SwiftProtobuf`'s generated serialization code (`Scip.pb.swift`).
- Writes to the output path (default: `<repo>/index.scip`).
- Verifies the file was written successfully; errors if disk is full or path is unwritable.

## Platform Constraints

### macOS-Only

`scip-swift` targets macOS (minimum: macOS 14) because:

1. **Xcode and Apple SDKs** — indexing projects that import `UIKit`, `WatchKit`, or `WidgetKit` requires the iOS/watchOS/macOS SDKs, which Apple only ships for macOS.
2. **IndexStore.framework** — Apple's compiler indexing framework is part of the Xcode toolchain on macOS.
3. **libIndexStore.dylib** — Located in the Xcode toolchain; only available on macOS.

**Consequence**: Pure Swift packages without Apple-framework imports *could* theoretically build on Linux, but `scip-swift` itself does not target Linux.

### Swift Version Pinning

- `Package.swift` specifies `swift-tools-version 6.2`
- `.swift-version` pins the toolchain to `6.2.4`
- USR format is not guaranteed stable across Swift versions by Apple
- Indexing with a different toolchain version is not tested or supported

**See also**: [project-overview-pdr.md](./project-overview-pdr.md) "Known Limitations" section.

## Data Flow: End-to-End Example

Given a simple SwiftPM package:

```swift
// Sources/Greeter.swift
public class Greeter {
  public func greet(name: String) -> String {
    return "Hello, \(name)!"
  }
}
```

**Step 1: Detection**
- `BuildBackendDetector` finds `Package.swift` → SwiftPM

**Step 2: Build**
- `SwiftPMBuildRunner` executes `swift build --enable-index-store`
- IndexStore created at `.build/.../index/store`

**Step 3: Load**
- `IndexStoreLoader` opens the IndexStore via IndexStoreDB
- `SwiftFileDiscovery` walks repo, finds `Sources/Greeter.swift`

**Step 4: Convert**
- For `Greeter.swift`, query IndexStore:
  - Occurrence: "Greeter" at line 1, col 14
    - Kind: class → `.class`
    - Role: definition → `Definition` bit
    - Symbol: USR kept opaque → `scip-swift swift <module> . <usr>.` (raw USR as a single descriptor term)
  - Occurrence: "greet" at line 2, col 15
    - Kind: function → `.method`
    - Role: definition → `Definition` bit
    - Symbol: USR kept opaque → `scip-swift swift <module> . <usr>.`
  - Occurrence: reference to `String` at line 2 (return type)
    - Kind: struct → `.struct`
    - Role: reference → `ReadAccess` bit
    - Symbol: external reference

**Step 5: Serialize**
- Create `Scip_Document` for `Sources/Greeter.swift` with occurrences
- Create `Scip_Index` with the document
- Add external symbol entries for `String` and standard library types
- Write to `index.scip`

## Integration Points

### With Sourcegraph

The generated `.scip` file is directly consumable by:
- `scip` CLI (`scip lint index.scip` validates; `scip upload` publishes)
- Sourcegraph Cloud (via SCIP upload API)
- Sourcegraph instances running SCIP-aware code intelligence

### With Editor Plugins

SCIP-based editor plugins (e.g., VS Code extensions, JetBrains IDE plugins) can:
- Parse the `.scip` file
- Resolve symbol definitions and cross-references
- Provide "go to definition", "find references", etc.

## Performance Characteristics

- **Time**: Proportional to repository size and number of symbol occurrences (typically seconds to minutes for large repos)
- **Memory**: Scales with the number of occurrences indexed; typically megabytes to low gigabytes
- **Disk I/O**: Dominated by build time; SCIP conversion is CPU-bound

## Future Architectural Considerations

- **Incremental indexing**: Cache IndexStore queries to avoid re-reading after a rebuild
- **Exact ranges**: Extend symbol occurrence queries to include full source-location ranges (if IndexStore API evolves)
- **Parallel conversion**: Multi-threaded processing of symbol occurrences
- **Streaming serialization**: For very large indexes, write protobuf messages incrementally to avoid memory buildup

## Incremental Indexing Architecture

The incremental cache lives in `Sources/scip-swift/Caching/` and is enabled whenever the cache is
persistent — i.e. when `--cache-dir` is passed or `--index-only` is used (default cache dir:
`<repo>/.scip-cache/`). Without either flag, `IndexCommand.indexOneRepo` falls back to a fresh
per-run temp directory and no caching occurs.

**Directory layout** (inside the cache dir):

```
<cacheDir>/docs/<sha256-hex>.scipdoc   — serialized Scip_Document protobufs, keyed by the composite
                                       (relativePath, content hash) key — SHA256(relativePath ‖ 0x00 ‖
                                       content hash) — so byte-identical files never share an entry
<cacheDir>/manifest.json               — global version manifest for cache invalidation
<cacheDir>/build-scratch/              — persistent SwiftPM scratch path (reused across runs)
<cacheDir>/index-db/                   — persistent IndexStoreDB database path
```

**Components**:

- **`CacheStore`** (`Caching/CacheStore.swift`) — file-based store exposing
  `documentCacheKey(relativePath:hash:)` (the composite-key derivation) plus
  `loadDocument(relativePath:hash:)` / `saveDocument(_:relativePath:hash:)` /
  `loadUSRMap(relativePath:hash:)` / `saveUSRMap(_:relativePath:hash:)` and
  `loadManifest()` / `saveManifest(_:)`. `invalidateAll()` deletes the whole cache directory.
- **`ContentHasher`** (`Caching/ContentHasher.swift`) — stateless SHA256 hashing via CryptoKit
  (`sha256Hex(of:)` for file paths or raw `Data`). A document's cache key derives from the
  SHA256 of its source file content combined with the file's repo-relative path
  (`CacheStore.documentCacheKey`), so an unchanged file maps to the same cache entry across
  runs while byte-identical files at different paths get distinct entries.
- **`IndexManifest`** (`Caching/IndexManifest.swift`) — `Codable` record with four fields that
  trigger **global** invalidation on any mismatch:
  - `toolchainVersion` — Swift compiler version (USR format is compiler-version sensitive)
  - `converterVersion` — `scip-swift` version (mapping-logic changes)
  - `indexstoreDbRevision` — pinned indexstore-db git revision (currently `"c993f4fb"` in
    `Commands/IndexCommand.swift`; store format changes)
  - `buildToolName` — `"swiftpm"` vs `"xcodebuild"` (different index data)

**Flow in `SCIPIndexBuilder.build()`** (when a `CacheStore` is attached):

1. For each discovered `.swift` file, compute the content hash
   (`ContentHasher.sha256Hex(of: filePath)`) and the file's repo-relative path.
2. If a cached `Scip_Document` exists for that path+hash composite key **and** the IndexStoreDB
   has at least one unit for the file (`dateOfLatestUnitFor(filePath:) != nil`), reuse it as-is.
3. Otherwise build a fresh document and, if the hash is available, persist it via
   `saveDocument(_:relativePath:hash:)`.
4. Cache writes are best-effort (`try?`) — a read-only cache dir never fails the run.

Manifest handling happens in `IndexCommand.indexOneRepo`: on any version mismatch (or a missing
manifest) the cache is invalidated and a fresh manifest is written before building.

`--index-only` skips the build step entirely: `SwiftPMBuildRunner.findIndexStore(underScratchPath:configuration:)`
locates the previously produced IndexStore under the persistent `build-scratch` path; failure raises
`BuildError.indexStoreNotFoundForIndexOnly(expectedPath:)`.

## Cross-Repository Indexing (`index-many`)

`Commands/IndexManyCommand.swift` adds a second subcommand, `scip-swift index-many <repo>...`:

- Requires at least two repository paths (validated with `ArgumentParser`'s `ValidationError`).
- Indexes each repo independently by calling `IndexCommand.indexOneRepo(...)` with
  `symbolVersion` set to the repo's directory name (last path component), so symbols from
  different repos are namespaced by repo in the SCIP symbol string's `<version>` field.
- Without `--merge`: writes one `<repoId>.scip` per repo into `--output-dir` (default `.`).
- With `--merge`: combines all indexes via `ScipIndexMerger` and writes a single
  `--merged-output` (default `merged.scip`).

**`ScipIndexMerger`** (`SCIPMapping/ScipIndexMerger.swift`) — pure protobuf manipulation:

1. **Document path prefixing** — each document's `relativePath` is prefixed with its repo
   identifier (`"<repoId>/<relativePath>"`) to prevent duplicate-document warnings when two
   repos contain identically named files.
2. **Metadata** — the merged index takes the first input's metadata, then overwrites
   `projectRoot` with the current working directory (the presumed workspace root).
3. **External-symbol stripping** — any external symbol that is now *defined* in one of the merged
   documents is dropped, since cross-repo references that were external in a single-repo index
   become internal once the defining repo is included.
4. **Deduplication** — remaining external symbols are deduplicated by symbol string
   (first occurrence wins) and sorted by symbol string for deterministic output.

## Symbol Metadata Mapping (relationships, enclosing symbols, signatures)

Three mappers (added in v0.2.0) enrich `Scip_SymbolInformation` beyond kind and name; all are
called from `SCIPIndexBuilder.makeDocument`:

- **`RelationshipMapping`** (`SCIPMapping/RelationshipMapping.swift`) — converts IndexStoreDB
  `SymbolRelation` entries to `Scip_Relationship` messages, only on definition occurrences of
  non-local symbols. `.childOf` relations are skipped (they feed `enclosingSymbol` instead);
  `.overrideOf` relations become `isReference = true, isImplementation = true`; relations that
  produce no set flags are dropped. Limitation: Swift's IndexStoreDB populates relations on
  member occurrences only — type-level inheritance and protocol conformance do **not** produce
  relations, so relationship mapping effectively covers override relationships only.
- **Enclosing symbols** (in `SCIPIndexBuilder.makeDocument`) — for local symbols
  (IndexStoreDB `.local` property), the first `.childOf` relation's target USR is formatted via
  `SCIPSymbolFormatter.globalSymbolString` into `Scip_SymbolInformation.enclosingSymbol`,
  giving consumers the containing type/method context.
- **`SignatureMapping`** (`SCIPMapping/SignatureMapping.swift`) — reconstructs minimal Swift
  signatures (`"func greet(name:)"`, `"class Greeter"`, `"static var ..."`, etc.) as
  `Scip_Signature` messages (`language: "swift"`) attached as `signatureDocumentation`, improving
  hover tooltips from bare names. Signatures lack parameter and return types —
  IndexStoreDB's `Symbol.name` carries argument labels but not types.

`Scip_Occurrence` also gains a `generated` symbol-role bit when the file path passes through
`.build`, `DerivedData`, or `.index-build` (`SCIPIndexBuilder.isGeneratedPath`).

## Directory Structure Rationale

```
Sources/scip-swift/
├── ScipSwiftCommand.swift     — @main root; registers index (default) + index-many subcommands
├── Version.swift              — ScipSwiftVersion constant used in metadata and cache manifests
├── Commands/                  — ArgumentParser subcommands and pipeline coordination
│   ├── IndexCommand.swift     — default subcommand; owns cache/temp dir policy, one-repo pipeline
│   └── IndexManyCommand.swift — multi-repo indexing and merge orchestration
├── Build/                     — build-tool detection and subprocess orchestration
│   (detector, BuildRunner protocol + SwiftPM/Xcodebuild impls, errors, config enums)
├── IndexStore/                — IndexStoreDB loading and .swift file discovery
├── Caching/                   — incremental-indexing support (CacheStore, ContentHasher, IndexManifest)
├── SCIPMapping/               — IndexStoreDB → SCIP conversion (SCIPIndexBuilder, pure mappers, merger)
├── Platform/                  — ToolchainInfo (pinned toolchain version for manifests/version output)
├── Protos/                    — vendored scip.proto (source of truth for Generated/)
└── Generated/                 — Scip.pb.swift, generated from Protos/scip.proto — never hand-edit
```

Each directory is a pipeline stage boundary: `Commands/` decides *what* to run, `Build/` produces
the IndexStore, `IndexStore/` reads it, `Caching/` short-circuits unchanged work, `SCIPMapping/`
converts to protobuf, and `Generated/` serializes. Mapping logic with no state lives in `enum`
namespaces with `static` functions, keeping stages testable in isolation.
