# Codebase Structure

**Analysis Date:** 2026-08-11

## Directory Layout

```
scip-swift/
├── Sources/scip-swift/          # All executable source code
│   ├── Build/                   # Build orchestration (SwiftPM + Xcode runners)
│   ├── Commands/                # ArgumentParser subcommands
│   ├── Generated/               # Vendored protobuf bindings (never hand-edit)
│   ├── IndexStore/              # IndexStoreDB access + file discovery
│   ├── Platform/                # Toolchain/libIndexStore resolution
│   ├── SCIPMapping/             # Core IndexStore→SCIP mapping logic
│   ├── ScipSwiftCommand.swift   # @main entry point
│   └── Version.swift            # Version constant
├── Tests/scip-swiftTests/       # Swift Testing test suites
├── Fixtures/MiniSwiftPackage/   # Real Swift package for integration tests
├── Protos/                      # Vendored scip.proto + generation script
├── docs/                        # Project documentation (PDR, architecture, standards)
├── .github/workflows/           # CI (macOS-only)
├── Package.swift                # SwiftPM manifest
├── .swift-version               # Pinned toolchain (6.2.4)
└── CLAUDE.md / README.md        # Project instructions
```

## Directory Purposes

**`Sources/scip-swift/Build/`:**
- Purpose: Build the target repo with indexing enabled and locate the IndexStore output
- Contains: 9 Swift files (~425 lines total) — build tool detection, two `BuildRunner` implementations, subprocess management, error types
- Key files: `BuildBackendDetector.swift` (auto-detect SwiftPM vs Xcode), `SwiftPMBuildRunner.swift`, `XcodebuildBuildRunner.swift`, `SubprocessRunner.swift`, `BuildError.swift`
- Subdirectories: None (flat)

**`Sources/scip-swift/Commands/`:**
- Purpose: ArgumentParser subcommand definitions
- Contains: 1 file — `IndexCommand.swift` (81 lines)
- Key files: `IndexCommand.swift` — the sole subcommand and pipeline coordinator
- Subdirectories: None

**`Sources/scip-swift/Generated/`:**
- Purpose: Swift protobuf bindings for the SCIP schema — vendored, never hand-edited
- Contains: `Scip.pb.swift` (3190 lines, auto-generated from `Protos/scip.proto`)
- Special: Regenerate via `Protos/generate.sh` (requires `brew install protobuf swift-protobuf`); do NOT edit

**`Sources/scip-swift/IndexStore/`:**
- Purpose: Open IndexStoreDB and discover `.swift` files in the target repo
- Contains: `IndexStoreLoader.swift` (17 lines), `SwiftFileDiscovery.swift` (26 lines)
- Key files: `IndexStoreLoader.open(storePath:databasePath:)` loads IndexStoreDB against `libIndexStore.dylib`
- Subdirectories: None

**`Sources/scip-swift/Platform/`:**
- Purpose: Resolve the active Swift toolchain
- Contains: `ToolchainInfo.swift` (32 lines)
- Key files: `ToolchainInfo.libIndexStorePath` — shells out to `xcrun --find swift`, then resolves `<toolchain>/usr/lib/libIndexStore.dylib`

**`Sources/scip-swift/SCIPMapping/`:**
- Purpose: The core mapping layer — IndexStoreDB occurrences → SCIP protobuf messages
- Contains: 5 files (~316 lines total) — 1 builder + 4 pure-function mappers
- Key files: `SCIPIndexBuilder.swift` (119 lines, main loop), `SCIPSymbolFormatter.swift` (77 lines, symbol string formatting + `LocalSymbolNumberer`), `SymbolKindMapping.swift` (70 lines), `PositionMapping.swift` (29 lines), `SymbolRoleMapping.swift` (21 lines)
- Subdirectories: None

## Key File Locations

**Entry Points:**
- `Sources/scip-swift/ScipSwiftCommand.swift` — `@main`, registers `IndexCommand` as default subcommand
- `Sources/scip-swift/Commands/IndexCommand.swift` — pipeline coordinator (detect → build → map → serialize → write)

**Configuration:**
- `Package.swift` — SwiftPM manifest (single executable + test target, 3 dependencies)
- `.swift-version` — pins toolchain to 6.2.4
- `.github/workflows/ci.yml` — CI config (macOS 26 runner, `swift build` + `swift test`)

**Core Logic:**
- `Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift` — the main mapping loop
- `Sources/scip-swift/SCIPMapping/SCIPSymbolFormatter.swift` — USR → SCIP symbol string
- `Sources/scip-swift/SCIPMapping/SymbolKindMapping.swift` — IndexStoreDB `Symbol.Kind` → SCIP kind
- `Sources/scip-swift/SCIPMapping/SymbolRoleMapping.swift` — `SymbolRole` bits → SCIP role bits
- `Sources/scip-swift/SCIPMapping/PositionMapping.swift` — 1-based anchor → 0-based half-open range

**Testing:**
- `Tests/scip-swiftTests/` — 5 test files (Swift Testing `@Suite`/`@Test`, not XCTest)
- `Fixtures/MiniSwiftPackage/` — minimal real Swift package used by integration tests

**Documentation:**
- `docs/system-architecture.md` — full architecture breakdown + end-to-end example
- `docs/code-standards.md` — patterns catalog (enum namespaces, protocol abstraction, error types)
- `docs/project-overview-pdr.md` — product requirements document
- `docs/project-roadmap.md` — roadmap and milestones
- `docs/research-scip-swift-limitations.md` — deep-dive on known and undocumented limitations
- `CLAUDE.md` — project instructions for AI assistants
- `README.md` — user-facing documentation

## Naming Conventions

**Files:**
- PascalCase matching the primary type: `BuildError.swift` contains `enum BuildError`, `SCIPIndexBuilder.swift` contains `struct SCIPIndexBuilder`
- Acronyms fully capitalized: `SCIPSymbolFormatter`, `ScipSwiftCommand` (SCIP in type names)
- Test files mirror the module name + `Tests`: `SymbolKindMappingTests.swift` tests `SymbolKindMapping`

**Directories:**
- PascalCase: `Build/`, `IndexStore/`, `SCIPMapping/`, `Generated/`
- Singular for functional areas (not pluralized collections)

**Types:**
- `enum` for stateless mappers: `SymbolKindMapping`, `SymbolRoleMapping`, `PositionMapping`, `SCIPSymbolFormatter`, `BuildBackendDetector`
- `struct` for data carriers and the one stateful mapper: `IndexStoreBuildResult`, `LocalSymbolNumberer`, `SCIPIndexBuilder`
- `protocol` for abstractions: `BuildRunner`

## Where to Add New Code

**New mapper (e.g., RelationshipMapping):**
- Implementation: `Sources/scip-swift/SCIPMapping/RelationshipMapping.swift` as `enum RelationshipMapping { static func ... }`
- Wire it in: `SCIPIndexBuilder.makeDocument()` — call the mapper inside the occurrence loop
- Tests: `Tests/scip-swiftTests/RelationshipMappingTests.swift` as `@Suite("RelationshipMapping") struct RelationshipMappingTests`

**New build backend (e.g., BazelBuildRunner):**
- Implementation: `Sources/scip-swift/Build/BazelBuildRunner.swift` conforming to `BuildRunner`
- Wire it in: Add a case to `BuildTool` enum, extend `BuildBackendDetector.detect()`, add a branch in `IndexCommand.produceIndexStore()`
- Tests: `Tests/scip-swiftTests/BazelBuildRunnerTests.swift`

**New CLI option:**
- Definition: `Sources/scip-swift/Commands/IndexCommand.swift` — add `@Option` or `@Flag` property
- Usage: In `IndexCommand.run()` or `produceIndexStore()`

**New test:**
- Unit test: `Tests/scip-swiftTests/<ModuleName>Tests.swift` using `@Suite`/`@Test`/`#expect`
- Integration test: Extend `IntegrationTests.swift` or add a new fixture under `Fixtures/`

## Special Directories

**`Sources/scip-swift/Generated/`:**
- Purpose: Auto-generated protobuf bindings
- Source: `Protos/generate.sh` runs `protoc` + `protoc-gen-swift` against `Protos/scip.proto`
- Committed: Yes (so consumers don't need protobuf toolchain to build)

**`Fixtures/MiniSwiftPackage/`:**
- Purpose: Real SwiftPM package for end-to-end integration testing (not mocked)
- Contains: `Package.swift`, `Sources/MiniSwiftPackage/Greeter.swift` (a simple `struct Greeter` with `greet()` and `name`)
- Committed: Yes — integration tests shell out to real `swift build` against this

**`Protos/`:**
- Purpose: Vendored SCIP schema and generation script
- Contains: `scip.proto` (35KB, upstream from `sourcegraph/scip`), `generate.sh`
- Committed: Yes

---

*Structure analysis: 2026-08-11*
*Update when directory structure changes*
