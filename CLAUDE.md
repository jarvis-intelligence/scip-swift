# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`scip-swift` is a CLI that converts a Swift repo's compiler index (IndexStoreDB) into a real
`scip.proto` SCIP index. It builds the target repo with indexing enabled, reads the resulting
IndexStore, and maps occurrences/symbols to SCIP protobuf messages.

## Commands

```sh
swift build                              # debug build
swift build -c release                   # release build -> .build/release/scip-swift
swift test                                # run all tests (unit + integration)
swift test --filter SCIPSymbolFormatter   # run one @Suite by name
swift test --filter "SymbolKindMapping/kinds with no SCIP counterpart fall back to unspecifiedKind"  # one @Test
```

Regenerate vendored protobuf bindings (only after `Protos/scip.proto` changes upstream):

```sh
brew install protobuf swift-protobuf
Protos/generate.sh
```

Toolchain is pinned in `.swift-version` (currently `6.2.4`); USR stability across Swift versions
isn't guaranteed, so don't test/build with a different toolchain without a reason.

Tests use **Swift Testing** (`@Suite`/`@Test` with string descriptions), not XCTest —
`Tests/scip-swiftTests/*.swift` is the pattern to follow for new tests. `IntegrationTests.swift`
shells out to a real `swift build` against `Fixtures/MiniSwiftPackage` (no mocks) — it's slower
than the unit tests, so prefer `--filter` when iterating on a single mapper.

CI (`.github/workflows/ci.yml`) runs `swift build` + `swift test` on `macos-15`; this tool is
macOS-only (indexing Apple-platform imports needs Xcode + iOS SDK, and `libIndexStore.dylib` only
ships on macOS) — don't try to make the build/test pipeline pass on Linux.

## Architecture

Single executable target (`Sources/scip-swift/`) as a five-stage pipeline; see
`docs/system-architecture.md` for the full breakdown and `docs/diagrams/system-architecture.png`
for the visual.

1. **CLI** — `ScipSwiftCommand.swift` (ArgumentParser root, dispatches to `IndexCommand`
   subcommand, which is also the `defaultSubcommand` so the bare `scip-swift <repo>` form works).
   `Commands/IndexCommand.swift` coordinates the whole pipeline and owns the temp work directory.
2. **Build orchestration** (`Build/`) — `BuildBackendDetector` picks `swiftpm` vs `xcodebuild`
   (prefers `.xcworkspace` > `.xcodeproj` > `Package.swift`) and hands off to a `BuildRunner`
   implementation (`SwiftPMBuildRunner` / `XcodebuildBuildRunner`, both via `SubprocessRunner`).
   Each runner's job is to build with indexing-while-building enabled and return the IndexStore
   path as `IndexStoreBuildResult`. `BuildError` is exhaustive — no generic error strings; build
   failures carry the last 50 lines of subprocess output.
3. **Index access** (`IndexStore/`) — `IndexStoreLoader` opens the IndexStoreDB at the runner's
   output path (locates `libIndexStore.dylib` via `xcrun --find swift`); `SwiftFileDiscovery` walks
   the repo for `.swift` files, skipping `.build`/`.git`/`.swiftpm`/`DerivedData`/`Pods`/`.index-build`.
4. **SCIP mapping** (`SCIPMapping/`) — `SCIPIndexBuilder` is the main loop: for each discovered file,
   query IndexStoreDB occurrences, convert each to `Scip_Occurrence`/`Scip_SymbolInformation`, track
   defined vs. referenced-but-undefined symbols for `external_symbols`. It delegates to four stateless
   pure-function mappers (see below), then serializes via generated `Generated/Scip.pb.swift`.
5. **Output** — serialized `Scip_Index` written to `.scip` (default `<repo>/index.scip`).

### The four pure mappers

Kept side-effect-free and exhaustively-switched on purpose (compile-time safety net if
IndexStoreDB adds new enum cases):

- `SCIPSymbolFormatter` — wraps the raw compiler USR as an opaque, escaped SCIP symbol string
  (no demangling — see README "Known limitations"). `LocalSymbolNumberer` assigns stable
  per-USR `local <n>` IDs for locally-scoped symbols.
- `SymbolKindMapping` — IndexStoreDB `Symbol.Kind`/subKind → `Scip_SymbolInformation.Kind`.
- `SymbolRoleMapping` — IndexStoreDB `SymbolRole` bits → SCIP `SymbolRole` bits. Note: real
  `scip.proto` has no call-specific bit, so call sites ride along on `.reference`.
- `PositionMapping` — IndexStoreDB gives a single 1-based anchor point; SCIP wants a 0-based
  half-open range, so the end column is *approximated* from the symbol's display-name length
  (exact for simple identifiers, can drift for compound names like `greet(name:)`).

### Conventions worth preserving

- Stateless mapping logic is an `enum` namespace with `static` functions, not a struct/class —
  signals "no constructor needed" (`SymbolKindMapping`, `BuildBackendDetector`, etc.).
- `Protos/scip.proto` and `Generated/Scip.pb.swift` are vendored from upstream `sourcegraph/scip`
  — never hand-edit `Generated/Scip.pb.swift`; regenerate instead (see Commands above).
- 2-space indentation throughout.

More detail: `docs/system-architecture.md` (component breakdown + end-to-end example),
`docs/code-standards.md` (patterns catalog), `docs/project-overview-pdr.md` and
`docs/project-roadmap.md` (product/roadmap context).
