# scip-swift: Codebase Summary

A quick-reference guide to the repository structure and key modules.

## Repository Layout

```
scip-swift/
├── Package.swift                           # SwiftPM manifest
├── Package.resolved                        # Pinned dependency versions
├── .swift-version                          # Pinned toolchain: 6.2.4
├── README.md                               # User-facing installation & usage guide
├── LICENSE                                 # Apache-2.0
│
├── .github/workflows/ci.yml                # GitHub Actions: build + test on every push/PR
│
├── Protos/
│   ├── scip.proto                          # Vendored upstream scip.proto from sourcegraph/scip
│   └── generate.sh                         # Regenerate Swift bindings from scip.proto
│
├── Sources/scip-swift/
│   ├── ScipSwiftCommand.swift              # @main CLI entry point (ArgumentParser)
│   ├── Version.swift                       # Converter version constant
│   │
│   ├── Build/                              # Build tool detection & execution
│   │   ├── BuildBackendDetector.swift      # Auto-detects SwiftPM vs Xcode projects
│   │   ├── BuildTool.swift                 # BuildTool enum (swiftpm, xcodebuild)
│   │   ├── BuildConfiguration.swift        # BuildConfiguration enum (debug, release)
│   │   ├── SwiftPMBuildRunner.swift        # SwiftPM build orchestration
│   │   ├── XcodebuildBuildRunner.swift     # Xcode build orchestration
│   │   ├── XcodeProjectLocator.swift       # Locates .xcworkspace/.xcodeproj and resolves schemes
│   │   ├── SubprocessRunner.swift          # Process spawning with safe pipe handling
│   │   ├── BuildError.swift                # Build error enum with CustomStringConvertible
│   │   └── IndexStoreBuildResult.swift     # BuildRunner protocol + result struct
│   │
│   ├── IndexStore/                         # IndexStore discovery and querying
│   │   ├── IndexStoreLoader.swift          # Opens IndexStore via IndexStoreDB
│   │   └── SwiftFileDiscovery.swift        # Walks repo for .swift files (excludes common build dirs)
│   │
│   ├── SCIPMapping/                        # IndexStoreDB → SCIP protobuf conversion
│   │   ├── SCIPIndexBuilder.swift          # Main orchestrator: queries IndexStore, builds SCIP Index
│   │   ├── SCIPSymbolFormatter.swift       # Converts USR to SCIP symbol string + LocalSymbolNumberer struct
│   │   ├── SymbolKindMapping.swift         # Maps IndexStoreDB Symbol.kind to SCIP SymbolInformation.Kind
│   │   ├── SymbolRoleMapping.swift         # Maps IndexStoreDB SymbolRole bits to SCIP SymbolRole bits
│   │   └── PositionMapping.swift           # Converts 1-based point to 0-based range in SCIP
│   │
│   ├── Platform/
│   │   └── ToolchainInfo.swift             # Swift version constant, locates libIndexStore.dylib
│   │
│   └── Generated/
│       └── Scip.pb.swift                   # Vendored SwiftProtobuf bindings (~3190 lines, never hand-edit)
│
├── Tests/scip-swiftTests/
│   ├── SCIPSymbolFormatterTests.swift      # Unit tests for SCIP symbol formatting
│   ├── SymbolKindMappingTests.swift        # Unit tests for symbol kind enum mapping
│   ├── SymbolRoleMappingTests.swift        # Unit tests for symbol role bit mapping
│   └── IntegrationTests.swift              # End-to-end pipeline test (build → IndexStore → SCIP)
│
├── Fixtures/
│   └── MiniSwiftPackage/                   # Small SwiftPM package for integration tests
│       ├── Package.swift
│       └── Sources/MiniSwiftPackage/Greeter.swift  # Single test source file (a `struct`)
```

## Key Modules

### CLI Entry Point (`ScipSwiftCommand.swift`)

Uses `ArgumentParser` to expose:
- **Positional arg**: `repoPath` (defaults to current directory)
- **Options**:
  - `--output <path>` — where to write the `.scip` file (default: `<repo>/index.scip`)
  - `--build-tool swiftpm|xcodebuild` — override auto-detection
  - `--configuration debug|release` — forwarded to the build tool (default: `debug`)
  - `--scheme <name>` — Xcode scheme (only for xcodebuild; auto-detected if unique)
  - `--version` — print converter version and built-against Swift version

**Flow**: Detect build tool → build (with indexing enabled) → load IndexStore → convert to SCIP → serialize to file.

### Build System Abstraction (`Build/`)

The `BuildRunner` protocol provides a single abstraction over both SwiftPM and Xcode:

```swift
protocol BuildRunner {
  func produceIndexStore() throws -> IndexStoreBuildResult
}
```

Implementations:
- **`SwiftPMBuildRunner`**: Runs `swift build --configuration <c> --scratch-path <p> --enable-index-store` and locates the IndexStore in `<scratch-path>/<triple>/<configuration>/index/store`.
- **`XcodebuildBuildRunner`**: Runs `xcodebuild ... -derivedDataPath <p> COMPILER_INDEX_STORE_ENABLE=YES build` and reads `<derivedDataPath>/Index.noindex/DataStore`.

**Error handling**: `BuildError` enum covers: `cannotDetectBuildSystem`, `xcodebuildSchemeRequired`, `toolNotLaunchable`, `buildFailed`, `indexStoreNotProduced` — each with an actionable `description` property.

### IndexStore Querying (`IndexStore/`)

- **`IndexStoreLoader`**: Opens the IndexStore via `IndexStoreDB` using the active toolchain's `libIndexStore.dylib` (located via `xcrun --find swift`).
- **`SwiftFileDiscovery`**: Walks the repo for `.swift` source files, skipping build directories (`.build`, `.git`, `.swiftpm`, `DerivedData`, `Pods`, `.index-build`).

### SCIP Conversion Pipeline (`SCIPMapping/`)

**`SCIPIndexBuilder`** orchestrates the whole flow:
1. Open IndexStoreDB from the build's IndexStore path.
2. Discover all Swift files in the repo.
3. For each file, query IndexStore for all symbol occurrences.
4. For each occurrence, map to a SCIP `Occurrence` + `SymbolInformation`.
5. Track defined vs. referenced-but-undefined symbols to populate `Index.external_symbols` (required by SCIP spec).
6. Write the final protobuf `Index` to disk.

**Mapping modules**:
- **`SCIPSymbolFormatter`** — renders an IndexStoreDB `Symbol` into the canonical SCIP symbol string (`<scheme> <manager> <package> <version> <descriptor>` or `local <id>`), using the raw compiler USR verbatim as a single opaque descriptor term (no demangling). `LocalSymbolNumberer` assigns stable per-document IDs to symbols IndexStoreDB marks `.local`. Space-fields are escaped per the SCIP grammar; non-identifier USRs are backtick-wrapped.
- **`SymbolKindMapping`** — maps IndexStoreDB `Symbol.kind`/`subKind` to SCIP `SymbolInformation.Kind` (best-effort matching).
- **`SymbolRoleMapping`** — maps IndexStoreDB `SymbolRole` bits to SCIP `SymbolRole` bits. Note: SCIP has no call-specific role bit.
- **`SymbolRoleMapping`** — packs IndexStoreDB `SymbolRole` bits into SCIP's `Int32` bitfield (`scipRoles(for:)`). `write` is mutually exclusive with `read` (a `write`-implying role suppresses the read bit), and there is no call-specific bit in `scip.proto`, so `.call` contributes nothing beyond `.reference`.
- **`PositionMapping`** — converts IndexStoreDB's single anchor point (1-based line/UTF8-column) to SCIP's 0-based half-open range; end column is approximated from symbol display-name length.

### Generated Code (`Generated/Scip.pb.swift`)

Vendored Swift code generated from upstream `sourcegraph/scip/Protos/scip.proto` via SwiftProtobuf. ~3190 lines. **Never hand-edit**; regenerate via `Protos/generate.sh` if the `.proto` file is updated.

### Platform & Versioning

- **`ToolchainInfo.swift`** — pinned Swift version constant (`6.2.4`, kept in sync with `.swift-version`); provides the function to locate `libIndexStore.dylib`.
- **`Version.swift`** — converter version constant.

## Testing

- **Unit tests** in `Tests/scip-swiftTests/` cover mapping logic (`SymbolKindMapping`, `SymbolRoleMapping`, `SCIPSymbolFormatter`).
- **Integration test** (`IntegrationTests.swift`) runs the full pipeline against `Fixtures/MiniSwiftPackage/`.
- Unit tests use Swift Testing (`@Suite`/`@Test`); run all with `swift test`, or one suite with `swift test --filter SymbolKindMapping`. The integration test shells out to a real `swift build` (no mocks), so it's slower than the unit suites.

## Dependencies

| Dependency | Purpose | URL |
|---|---|---|
| `swiftlang/indexstore-db` | IndexStore querying API | https://github.com/swiftlang/indexstore-db |
| `apple/swift-protobuf` | Protobuf code generation | https://github.com/apple/swift-protobuf |
| `apple/swift-argument-parser` | CLI argument parsing | https://github.com/apple/swift-argument-parser |
| `sourcegraph/scip` (vendored) | SCIP protobuf specification | https://github.com/sourcegraph/scip |

## Conventions

- **2-space indentation** throughout.
- **Enums as namespaces** for stateless utility logic (e.g., `SymbolKindMapping`, `SymbolRoleMapping`).
- **Errors with CustomStringConvertible** for actionable user-facing messages (`BuildError`).
- **Protocol-based build runner abstraction** to support multiple build systems without duplicating pipeline logic.
- **Doc comments** in code cite the `design.md` decision or requirement they implement.
