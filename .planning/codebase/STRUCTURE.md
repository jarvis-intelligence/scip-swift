---
title: STRUCTURE
focus: arch
last_mapped_commit: 34a8c1e
---

# STRUCTURE

**Analysis Date:** 2026-08-11

Directory layout, key locations, and naming conventions for `scip-swift`.

## Top-Level Layout

```
scip-swift/
├── Package.swift                  # SwiftPM manifest (swift-tools-version 6.2, macOS(.v14))
├── Package.resolved               # Pinned dependency revisions
├── .swift-version                 # Toolchain pin: 6.2.4
├── .gitignore                     # Ignores .build/, .swiftpm/, *.scip; re-includes Build/
├── CLAUDE.md                      # Agent guidance (architecture + commands)
├── README.md                      # User-facing docs
├── LICENSE                        # Apache-2.0
│
├── .github/workflows/ci.yml       # CI: build + test on macos-26
├── Protos/
│   ├── scip.proto                 # Vendored upstream SCIP schema (sourcegraph/scip)
│   └── generate.sh                # Regenerate Swift bindings (protoc + protoc-gen-swift)
├── Sources/scip-swift/            # Sole executable target (see below)
├── Tests/scip-swiftTests/         # Swift Testing test target
├── Fixtures/MiniSwiftPackage/     # Fixture repo for integration tests
└── docs/                          # Design docs, roadmap, research, diagrams
```

## Source Target — `Sources/scip-swift/`

The single executable target. Organized by pipeline stage (mirrors the architecture layers).

```
Sources/scip-swift/
├── ScipSwiftCommand.swift            # @main entry (ArgumentParser root)
├── Commands/
│   └── IndexCommand.swift            # defaultSubcommand; orchestrates the whole pipeline
├── Build/                            # Stage 2: build orchestration
│   ├── BuildTool.swift               # enum BuildTool { swiftpm, xcodebuild } (ExpressibleByArgument)
│   ├── BuildConfiguration.swift      # enum BuildConfiguration { debug, release }
│   ├── BuildBackendDetector.swift    # auto-detect swiftpm vs xcodebuild from repo contents
│   ├── BuildRunner                   # (protocol in IndexStoreBuildResult.swift)
│   ├── SwiftPMBuildRunner.swift      # swift build --enable-index-store runner
│   ├── XcodebuildBuildRunner.swift   # xcodebuild runner (signing disabled, .arguments is testable)
│   ├── XcodeProjectLocator.swift     # find .xcworkspace/.xcodeproj + resolve scheme
│   ├── SubprocessRunner.swift        # Process wrapper + resolveExecutable(named:)
│   ├── BuildError.swift              # exhaustive typed error enum
│   └── IndexStoreBuildResult.swift   # BuildRunner protocol + result struct
├── IndexStore/                       # Stage 3: open + query the IndexStore
│   ├── IndexStoreLoader.swift        # open IndexStoreDB via libIndexStore.dylib
│   └── SwiftFileDiscovery.swift      # walk repo for .swift files (skip build/dep dirs)
├── SCIPMapping/                      # Stage 4: IndexStoreDB → SCIP protobuf
│   ├── SCIPIndexBuilder.swift        # main loop: occurrences → Documents/Symbols/external_symbols
│   ├── SCIPSymbolFormatter.swift     # USR → SCIP symbol string; LocalSymbolNumberer struct
│   ├── SymbolKindMapping.swift       # Symbol.Kind/subKind → Scip_SymbolInformation.Kind
│   ├── SymbolRoleMapping.swift       # SymbolRole bits → Scip_SymbolRole bits
│   └── PositionMapping.swift         # 1-based anchor → 0-based half-open range
├── Platform/
│   └── ToolchainInfo.swift           # pinnedSwiftVersion + libIndexStoreDylibPath()
├── Version.swift                     # ScipSwiftVersion.version = "0.1.2"
└── Generated/
    └── Scip.pb.swift                 # ~3190-line generated protobuf bindings — NEVER hand-edit
```

## Test Target — `Tests/scip-swiftTests/`

One test file per unit, plus one end-to-end integration suite. Uses **Swift Testing**
(`@Suite`/`@Test`), not XCTest.

```
Tests/scip-swiftTests/
├── SCIPSymbolFormatterTests.swift     # symbol-string formatting + LocalSymbolNumberer
├── SymbolKindMappingTests.swift       # kind/subKind → SCIP kind
├── SymbolRoleMappingTests.swift       # role bit mapping (incl. .call ride-along)
├── XcodebuildBuildRunnerTests.swift   # XcodebuildBuildRunner.arguments assertions (no real xcodebuild)
└── IntegrationTests.swift             # full pipeline vs Fixtures/MiniSwiftPackage (shells out)
```

## Fixtures

```
Fixtures/MiniSwiftPackage/
├── Package.swift                      # minimal SwiftPM package
└── Sources/MiniSwiftPackage/Greeter.swift   # Greeter struct with greet()/name property
```
Used only by `IntegrationTests.swift`. There is **no Xcode fixture** — the xcodebuild path is
validated by argument-list assertions only.

## Key Locations (quick reference)

| Need | Look at |
|---|---|
| Add a CLI flag | `Sources/scip-swift/Commands/IndexCommand.swift` |
| Change build invocation | `Sources/scip-swift/Build/*BuildRunner.swift` |
| Change symbol/role/kind mapping | `Sources/scip-swift/SCIPMapping/*Mapping.swift` |
| Change the main indexing loop | `Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift` |
| Regenerate proto bindings | `Protos/generate.sh` (after editing `Protos/scip.proto`) |
| Bump version | `Sources/scip-swift/Version.swift` |
| CI config | `.github/workflows/ci.yml` |

## Naming Conventions

- **Files** are named after their primary type (`BuildError.swift` → `enum BuildError`,
  `SCIPIndexBuilder.swift` → `struct SCIPIndexBuilder`). One primary type per file.
- **Directories** group by pipeline stage / responsibility (`Build/`, `IndexStore/`,
  `SCIPMapping/`, `Platform/`, `Commands/`, `Generated/`).
- **Types**: `PascalCase`. Mapping namespaces and stateless utilities are `enum`; data carriers and
  the orchestrator are `struct`; `BuildRunner` is a `protocol`.
- **Generated code** lives under `Generated/` with a capitalized proto-derived name
  (`Scip.pb.swift`, types prefixed `Scip_`).

## Documentation

`docs/` contains: `codebase-summary.md`, `system-architecture.md`, `code-standards.md`,
`project-overview-pdr.md`, `project-roadmap.md`, `research-scip-swift-limitations.md`, and
`diagrams/` (`system-architecture.png`, `.excalidraw`, `architecture-diagram.html`).

---
*arch focus analysis: 2026-08-11*
<!-- refreshed: 2026-08-11 -->
