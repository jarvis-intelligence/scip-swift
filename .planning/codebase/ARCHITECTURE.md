---
title: ARCHITECTURE
focus: arch
last_mapped_commit: 34a8c1e
---

# ARCHITECTURE

**Analysis Date:** 2026-08-11

System design and data flow for `scip-swift`.

## Architectural Pattern

A **linear five-stage pipeline** in a single executable target. There is no long-running process,
no plugin system, and no request/response model: the CLI ingests a repo path and emits a single
`.scip` file. Each stage hands a plain-data value to the next.

```
CLI (ArgumentParser)
   │  repo path + options
   ▼
Build orchestration ──► IndexStoreBuildResult { indexStorePath }
   │  (shells out to swift build / xcodebuild)
   ▼
IndexStore access ──► IndexStoreDB handle + [swift file paths]
   │  (opens libIndexStore.dylib via IndexStoreDB)
   ▼
SCIP mapping ──► Scip_Index (protobuf message)
   │  (stateless pure-function mappers)
   ▼
Output ──► serializedData() written to .scip file
```

The entry point is `Sources/scip-swift/ScipSwiftCommand.swift` (`@main`), which delegates to the
`IndexCommand` subcommand (`Sources/scip-swift/Commands/IndexCommand.swift`) — also the
`defaultSubcommand`, so the bare `scip-swift <repo>` form works. `IndexCommand.run()` owns the
whole pipeline and the per-run temp work directory.

## Layers (by directory)

### 1. CLI — `ScipSwiftCommand.swift`, `Commands/IndexCommand.swift`
ArgumentParser root + subcommand. `IndexCommand` parses `repoPath`, `--output`, `--build-tool`,
`--configuration`, `--scheme`; resolves the build tool (explicit or auto-detected); creates a
temp work dir; and coordinates the four remaining stages. All work-directory paths are composed
from `NSTemporaryDirectory()/scip-swift-<uuid>/`.

### 2. Build orchestration — `Sources/scip-swift/Build/`
Responsibility: build the target repo with indexing-while-building enabled and return the path to
the resulting IndexStore as an `IndexStoreBuildResult`.

- `BuildBackendDetector.detect(repoPath:)` picks `.swiftpm` vs `.xcodebuild` — prefers `Package.swift`,
  else any `.xcworkspace`/`.xcodeproj` entry, else throws `BuildError.cannotDetectBuildSystem`.
- `BuildRunner` protocol (`IndexStoreBuildResult.swift`) with two implementations:
  - `SwiftPMBuildRunner` — `swift build --enable-index-store --scratch-path <p>`, then locates
    `<scratch>/<triple>/<config>/index/store`.
  - `XcodebuildBuildRunner` — `xcodebuild … COMPILER_INDEX_STORE_ENABLE=YES CODE_SIGNING_*=NO`,
    IndexStore at `<derivedData>/Index.noindex/DataStore`.
- `XcodeProjectLocator` resolves `-workspace`/`-project` args and the scheme (explicit, or the
  single shared scheme from `xcodebuild -list -json`).
- `SubprocessRunner` — `Process` wrapper with concurrent stdout/stderr reads (avoids pipe-buffer
  deadlock) and `resolveExecutable(named:)` via `/usr/bin/env which`.
- `BuildError` — exhaustive error enum, `CustomStringConvertible`; carries last subprocess output.

### 3. IndexStore access — `Sources/scip-swift/IndexStore/`
- `IndexStoreLoader.open(storePath:databasePath:)` — instantiates `IndexStoreDB` with the dylib
  resolved by `ToolchainInfo.libIndexStoreDylibPath()`.
- `SwiftFileDiscovery.swiftFiles(underRepoPath:)` — walks the repo for `.swift` files, skipping
  `.build`, `.git`, `.swiftpm`, `DerivedData`, `Pods`, `.index-build`. Returns sorted paths.

### 4. SCIP mapping — `Sources/scip-swift/SCIPMapping/`
The core conversion. `SCIPIndexBuilder` is a `struct` (stateful, runs once) that drives the loop;
it delegates to four **stateless** pure-function mappers.

- `SCIPIndexBuilder.build()` (`SCIPIndexBuilder.swift`):
  1. Opens the IndexStoreDB.
  2. Builds `Scip_Metadata` (`toolInfo.name = "scip-swift"`, version, CLI args, `project_root`, utf8).
  3. For each discovered `.swift` file → `makeDocument(...)`:
     - Queries `indexStoreDB.symbolOccurrences(inFilePath:)`.
     - For each occurrence (sorted): builds the SCIP symbol string (local vs global), an
       `Scip_Occurrence` (symbol, roles via `SymbolRoleMapping`, range via `PositionMapping`),
       and a `Scip_SymbolInformation` (symbol, displayName, kind via `SymbolKindMapping`).
     - Definition occurrences populate `document.symbols`; non-local referenced occurrences are
       tracked for `external_symbols`.
  4. `external_symbols` = referenced-but-never-defined symbol infos (e.g. stdlib types), sorted.
- The four pure mappers:
  - `SCIPSymbolFormatter` — renders the canonical SCIP symbol string. Global symbols wrap the raw
    compiler USR as an opaque escaped descriptor term (`scip-swift <pm> <module> . <usr>.`);
    local symbols use `local <n>`. `LocalSymbolNumberer` assigns stable per-document IDs.
  - `SymbolKindMapping` — IndexStoreDB `Symbol.Kind`/`subKind` → `Scip_SymbolInformation.Kind`
    (exhaustive switch; subKind overrides for subscript/getter/setter).
  - `SymbolRoleMapping` — IndexStoreDB `SymbolRole` bits → SCIP `SymbolRole` bits (definition,
    write→writeAccess, read/reference→readAccess).
  - `PositionMapping` — 1-based anchor point → 0-based half-open `Scip_SingleLineRange`; end column
    approximated from display-name length (stops at first `(`).

### 5. Output
`index.serializedData().write(to:)` to `--output` or `<repo>/index.scip`
(`IndexCommand.run()`). Prints `Wrote N document(s) to <path>`.

## Key Abstractions

- **`BuildRunner` protocol** — decouples the pipeline from the concrete build tool; the mapping
  layer is agnostic to which runner produced the IndexStore.
- **Stateless `enum` namespaces** for pure mapping logic (`SymbolKindMapping`,
  `SymbolRoleMapping`, `PositionMapping`, `SCIPSymbolFormatter`, `BuildBackendDetector`,
  `SwiftFileDiscovery`, `IndexStoreLoader`, `SubprocessRunner`, `ToolchainInfo`,
  `XcodeProjectLocator`). Signals "no constructor needed."
- **`IndexStoreBuildResult`** — the plain-data handoff between build orchestration and mapping.
- **`BuildError`** — typed, exhaustive errors; no generic string errors.

## Data Flow (end-to-end example)

```
repo/Package.swift
  → BuildBackendDetector.detect → .swiftpm
  → SwiftPMBuildRunner.produceIndexStore → swift build --enable-index-store --scratch-path <tmp>/scratch
  → IndexStoreBuildResult(indexStorePath: "<tmp>/scratch/<triple>/debug/index/store")
  → SCIPIndexBuilder(repoPath, indexStorePath, databasePath: "<tmp>/index-db", buildToolName: "swiftpm", converterVersion)
  → IndexStoreLoader.open (loads libIndexStore.dylib)
  → SwiftFileDiscovery.swiftFiles → [repo/Sources/Foo.swift, …]
  → per file: IndexStoreDB.symbolOccurrences → Scip_Occurrence + Scip_SymbolInformation
  → Scip_Index { metadata, documents, externalSymbols }
  → serializedData() → repo/index.scip
```

## Entry Points

- `@main ScipSwiftCommand` (`Sources/scip-swift/ScipSwiftCommand.swift`) — the only entry point.
- `IndexCommand.run()` is the pipeline orchestrator.

## Cross-Cutting Concerns

- **Toolchain pinning** — `ToolchainInfo.pinnedSwiftVersion` (`6.2.4`) and `.swift-version`; USR
  stability across toolchain versions is not guaranteed.
- **macOS-only** — `libIndexStore.dylib` and Apple SDKs are macOS-only; enforced by host
  requirements, not runtime checks.
- **Temp-dir isolation** — each run gets its own `NSTemporaryDirectory()` work dir; cleaned up by
  OS, not explicitly by the tool (tests use `defer { removeItem }`).

---
*arch focus analysis: 2026-08-11*
<!-- refreshed: 2026-08-11 -->
