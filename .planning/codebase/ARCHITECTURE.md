# Architecture

**Analysis Date:** 2026-08-11

## Pattern Overview

**Overall:** Five-stage single-executable CLI pipeline (build → index access → map → serialize → output)

**Key Characteristics:**
- Single executable target, no library product
- Linear pipeline — each stage's output feeds the next, no branching or async
- Stateless pure-function mappers (side-effect-free enum namespaces)
- In-memory processing — no persistent state between runs; every invocation rebuilds from scratch
- Compiler-as-index-source — reads the Swift compiler's own IndexStore (same data Xcode/SourceKit-LSP use)

## Layers

**CLI Layer:**
- Purpose: Parse arguments, dispatch to subcommand, own temp-directory lifecycle
- Contains: `ScipSwiftCommand` (`@main` root), `IndexCommand` (sole/default subcommand)
- Location: `Sources/scip-swift/ScipSwiftCommand.swift`, `Sources/scip-swift/Commands/IndexCommand.swift`
- Depends on: Build orchestration + SCIP mapping layers
- Used by: User invocation (`scip-swift <repo>`)

**Build Orchestration Layer:**
- Purpose: Build the target repo with indexing enabled; locate the resulting IndexStore
- Contains: `BuildBackendDetector`, `SwiftPMBuildRunner`, `XcodebuildBuildRunner`, `XcodeProjectLocator`, `SubprocessRunner`, `BuildError`, `BuildTool`, `BuildConfiguration`, `IndexStoreBuildResult`
- Location: `Sources/scip-swift/Build/`
- Depends on: `SubprocessRunner` (Foundation `Process`), `ToolchainInfo` (Platform layer)
- Used by: `IndexCommand.produceIndexStore()`

**Index Access Layer:**
- Purpose: Open the IndexStoreDB at the build output path; discover `.swift` files in the repo
- Contains: `IndexStoreLoader.open(storePath:databasePath:)`, `SwiftFileDiscovery.swiftFiles(underRepoPath:)`
- Location: `Sources/scip-swift/IndexStore/`
- Depends on: `IndexStoreDB` package, `ToolchainInfo` (locates `libIndexStore.dylib`)
- Used by: `SCIPIndexBuilder.build()`

**SCIP Mapping Layer:**
- Purpose: Convert IndexStoreDB occurrences/symbols into SCIP protobuf messages
- Contains: `SCIPIndexBuilder` (main loop + state), four pure mappers (`SCIPSymbolFormatter`, `SymbolKindMapping`, `SymbolRoleMapping`, `PositionMapping`)
- Location: `Sources/scip-swift/SCIPMapping/`
- Depends on: `IndexStoreDB`, `Generated/Scip.pb.swift`
- Used by: `IndexCommand.run()` (calls `builder.build()`)

**Platform Layer:**
- Purpose: Resolve the active toolchain and locate `libIndexStore.dylib`
- Contains: `ToolchainInfo` (`pinnedSwiftVersion`, `libIndexStorePath` via `xcrun --find swift`)
- Location: `Sources/scip-swift/Platform/ToolchainInfo.swift`
- Depends on: `Foundation.Process` (shells out to `xcrun`)
- Used by: `IndexStoreLoader`, `IndexCommand` (version string)

**Generated Layer (vendored):**
- Purpose: Swift protobuf bindings for the SCIP schema
- Contains: `Scip_Index`, `Scip_Document`, `Scip_Occurrence`, `Scip_SymbolInformation`, `Scip_SingleLineRange`, `Scip_Metadata`, `Scip_ToolInfo`, `Scip_SymbolRole`
- Location: `Sources/scip-swift/Generated/Scip.pb.swift` (3190 lines — never hand-edit; regenerate via `Protos/generate.sh`)
- Depends on: `SwiftProtobuf`
- Used by: SCIP mapping layer

## Data Flow

**Indexing a repository (the only flow):**

1. User runs `scip-swift <repoPath> [--output ...] [--build-tool ...] [--configuration ...] [--scheme ...]`
2. `ScipSwiftCommand` (the `@main`) dispatches to `IndexCommand` (the default subcommand)
3. `IndexCommand.run()` resolves `repoPath` to an absolute path
4. `BuildBackendDetector.detect(repoPath:)` picks `.swiftpm` (if `Package.swift` exists) or `.xcodebuild` (if `.xcworkspace`/`.xcodeproj` found); `--build-tool` overrides
5. A temp work directory is created under `$TMPDIR/scip-swift-<uuid>/`
6. `produceIndexStore(tool:repoPath:workDirectory:)` switches on the build tool:
   - `.swiftpm` → `SwiftPMBuildRunner` runs `swift build --scratch-path <tmp>/scratch --enable-index-store`, then finds `<scratch>/<triple>/<config>/index/store`
   - `.xcodebuild` → `XcodeProjectLocator` resolves workspace/project + scheme, `XcodebuildBuildRunner` runs `xcodebuild build -derivedDataPath <tmp>/derived-data COMPILER_INDEX_STORE_ENABLE=YES CODE_SIGNING_ALLOWED=NO ...`, IndexStore is at `<derived>/Index.noindex/DataStore`
7. `SCIPIndexBuilder` is initialized with the IndexStore path + a database path (`<workDir>/index-db`)
8. `builder.build()` opens IndexStoreDB, walks every `.swift` file (via `SwiftFileDiscovery`), queries occurrences per file:
   - Each occurrence → `SCIPSymbolFormatter` (symbol string) + `SymbolRoleMapping` (role bits) + `PositionMapping` (range) → `Scip_Occurrence`
   - Defined symbols collected into `document.symbols`; referenced-but-undefined symbols tracked for `external_symbols`
   - Locals (`.local` property) get `local <n>` IDs via `LocalSymbolNumberer`
9. `index.externalSymbols` = referenced symbols not in any document's defined set (needed for `scip lint`)
10. `index.serializedData()` written to `--output` or `<repo>/index.scip`
11. Temp directory is left in place (not explicitly cleaned up beyond OS temp eviction)

**State Management:**
- No persistent state — every run is independent and starts from a clean build
- Temp directory is created fresh per invocation via `UUID()`
- IndexStoreDB database path is under the temp directory (ephemeral)

## Key Abstractions

**Enum-as-stateless-namespace (pure mapper):**
- Purpose: Pure-function transformations from IndexStoreDB types to SCIP types — no instance state
- Examples: `SCIPSymbolFormatter`, `SymbolKindMapping`, `SymbolRoleMapping`, `PositionMapping`, `BuildBackendDetector`
- Pattern: `enum FooMapper { static func mapX(...) -> ScipY }` — using `enum` (not `struct`) signals "no instances, no constructor"

**BuildRunner protocol:**
- Purpose: Decouple the pipeline from a specific build tool
- Examples: `SwiftPMBuildRunner`, `XcodebuildBuildRunner`
- Pattern: Protocol with a single `produceIndexStore() throws -> IndexStoreBuildResult` method; `IndexCommand` switches on the `BuildTool` enum to pick the runner

**LocalSymbolNumberer (the one stateful mapper):**
- Purpose: Assign stable per-document `local <n>` IDs to locally-scoped symbols
- Location: `Sources/scip-swift/SCIPMapping/SCIPSymbolFormatter.swift` (bottom of file)
- Pattern: `struct` with `private var idsByUSR: [String: Int]`; a fresh instance is created per document

**BuildError (exhaustive error enum):**
- Purpose: Every build-pipeline failure mode has a named case with an actionable `CustomStringConvertible` message
- Location: `Sources/scip-swift/Build/BuildError.swift`
- Pattern: `enum BuildError: Error, CustomStringConvertible` with 5 cases — no generic error strings

## Entry Points

**CLI entry (`@main`):**
- Location: `Sources/scip-swift/ScipSwiftCommand.swift`
- Triggers: Running the `scip-swift` executable
- Responsibilities: Declare root command config, register `IndexCommand` as the sole subcommand

**Subcommand dispatch:**
- Location: `Sources/scip-swift/Commands/IndexCommand.swift`
- Triggers: Any `scip-swift [index] <args>` invocation (`index` is optional — it's the `defaultSubcommand`)
- Responsibilities: Parse args → detect build backend → create temp dir → run build → build SCIP index → write output

## Error Handling

**Strategy:** Swift typed errors (`Error` protocol) thrown and caught at `IndexCommand.run()` (ArgumentParser renders them to the user)

**Patterns:**
- `BuildError` — exhaustive 5-case enum; each case carries structured context (repoPath, tool name, exit code, output) and renders an actionable message via `CustomStringConvertible`
- `IndexStoreLoader` throws whatever `IndexStoreDB` throws (opaque to the caller — no wrapping)
- `SubprocessRunner.run()` throws `BuildError.toolNotLaunchable` if the executable can't be resolved
- No `try?` or `Result` types — errors propagate via `throws` up to the CLI boundary

## Cross-Cutting Concerns

**Logging:**
- Minimal: `print("Wrote \(n) document(s) to \(path)")` on success — no logging framework, no debug output
- Build failures surface the last 50 lines of subprocess output via `BuildError.buildFailed`

**Toolchain resolution:**
- `ToolchainInfo.libIndexStorePath` shells out to `xcrun --find swift`, then resolves `<toolchain>/usr/lib/libIndexStore.dylib` — happens at IndexStoreDB open time, not at startup

**File discovery filtering:**
- `SwiftFileDiscovery.skippedDirectoryNames` = `.build`, `.git`, `.swiftpm`, `DerivedData`, `Pods`, `.index-build` — prevents indexing dependency checkouts and build artifacts

---

*Architecture analysis: 2026-08-11*
*Update when major patterns change*
