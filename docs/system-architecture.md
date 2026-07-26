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

### 1. CLI Layer (`ScipSwiftCommand.swift`)

**Responsibility**: Parse user arguments, coordinate the pipeline, handle top-level errors.

**Inputs**:
- Positional: `repoPath` (target repository)
- Options: `--output`, `--build-tool`, `--configuration`, `--scheme`, `--version`

**Outputs**:
- `.scip` file (serialized protobuf Index) or error message

**Key logic**:
- Validates inputs (repo exists, output path is writable)
- Invokes `BuildBackendDetector` to choose build runner
- Calls `BuildRunner.produceIndexStore()` to get IndexStore path
- Delegates to `SCIPIndexBuilder` for conversion
- Handles serialization and file I/O

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
- Cleans up scratch directory after completion (optional, depends on implementation choice)

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
- Returns a set of SCIP roles (typically definition, reference, or both).

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
  - Occurrence: "class Greeter" at line 1, col 14
    - Kind: class → `.class`
    - Role: definition → `[.definition]`
    - Symbol: USR `_$s7Greeter0A0C` → `scip-swift swift Greeter/...`
  - Occurrence: "func greet" at line 2, col 15
    - Kind: function → `.method`
    - Role: definition → `[.definition]`
    - Symbol: USR `_$s7Greeter0A0C5greet4nameSSSH_tF` → `scip-swift swift Greeter/Greeter/greet(_:)`
  - Occurrence: reference to `String` at line 2 (return type)
    - Kind: struct → `.struct`
    - Role: reference → `[.reference]`
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
