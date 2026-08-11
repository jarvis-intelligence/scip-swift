---
title: INTEGRATIONS
focus: tech
last_mapped_commit: 34a8c1e
---

# INTEGRATIONS

**Analysis Date:** 2026-08-11

External services, native system integrations, and process boundaries for `scip-swift`.

`scip-swift` has **no network calls, no databases, and no auth providers**. All of its
"integrations" are local: it shells out to build-tool executables, loads a native dynamic library,
and reads/writes the local filesystem. This document describes those process and system boundaries.

## Process Integrations (subprocess shells)

The tool orchestrates external executables via `Sources/scip-swift/Build/SubprocessRunner.swift`
(thin wrapper over `Foundation.Process` with concurrent pipe reads to avoid deadlock).

| Executable | Invoked by | Purpose |
|---|---|---|
| `swift build` | `Sources/scip-swift/Build/SwiftPMBuildRunner.swift` | Build a SwiftPM repo with indexing enabled (`--enable-index-store`, custom `--scratch-path`); output is an IndexStore |
| `xcodebuild` | `Sources/scip-swift/Build/XcodebuildBuildRunner.swift` | Build an Xcode project/scheme with `COMPILER_INDEX_STORE_ENABLE=YES` and code signing disabled; output IndexStore lands in `<derivedData>/Index.noindex/DataStore` |
| `xcodebuild -list -json` | `Sources/scip-swift/Build/XcodeProjectLocator.swift` | Auto-resolve the single shared scheme when `--scheme` is omitted |
| `xcrun --find swift` | `Sources/scip-swift/Platform/ToolchainInfo.swift` | Locate the active toolchain root → derive `libIndexStore.dylib` path |
| `/usr/bin/env which <name>` | `SubprocessRunner.resolveExecutable` | Resolve an executable name to an absolute `PATH` lookup |

Executable resolution is centralized in `SubprocessRunner.resolveExecutable(named:)`; failures
surface as `BuildError.toolNotLaunchable`.

## Native Library Integration

- **`libIndexStore.dylib`** — loaded at runtime via `IndexStoreLibrary(dylibPath:)`
  (`Sources/scip-swift/IndexStore/IndexStoreLoader.swift`). Located by resolving the toolchain root
  from `xcrun --find swift` → `<toolchain>/usr/lib/libIndexStore.dylib`
  (`ToolchainInfo.libIndexStoreDylibPath()`). This dylib ships only with the macOS toolchain, which
  is why the tool is macOS-only.

## IndexStoreDB (the data source)

- Not a service — a Swift package (`indexstore-db`) that reads the compiler-produced IndexStore
  on disk into an in-process LMDB-backed database. Opened in
  `IndexStoreLoader.open(storePath:databasePath:)` with `waitUntilDoneInitializing: true`.
- The database path is a throwaway per-run temp directory
  (`IndexCommand.makeTemporaryDirectory()` → `…/index-db`).

## Filesystem I/O

| Path | Role |
|---|---|
| `<repo>` (CLI argument) | Target repo to index |
| `NSTemporaryDirectory()/scip-swift-<uuid>/` | Per-run work dir: `scratch/`, `derived-data/`, `index-db/` |
| `<repo>/index.scip` (default) or `--output <path>` | Serialized `Scip_Index` protobuf output |
| `<scratch>/<triple>/<config>/index/store` | SwiftPM-produced IndexStore (located by `SwiftPMBuildRunner.findIndexStore`) |
| `<derivedData>/Index.noindex/DataStore` | xcodebuild-produced IndexStore |

## Upstream Sourcegraph SCIP Schema

- `Protos/scip.proto` is **vendored** from `https://github.com/sourcegraph/scip`. Regeneration is
  manual (`Protos/generate.sh`); there is no runtime fetch of the schema.
- Output `.scip` files are designed to be consumed by standard SCIP tooling (the `scip` CLI,
  `codeintel`, Sourcegraph, editor plugins) — these are external consumers, not integrations this
  repo calls into.

## CI

- `.github/workflows/ci.yml` — GitHub Actions, runs on `macos-26` (provides Xcode 26 / Swift 6.2).
  Steps: print toolchain versions → `swift build --configuration debug` → `swift test --configuration debug`.
  No deploy step; releases are manual binary uploads.

## Non-Integrations (explicitly absent)

- No HTTP client, no `URLSession` usage, no network calls.
- No persistence layer (the IndexStoreDB LMDB db is ephemeral per run).
- No secrets, tokens, or credentials anywhere in the codebase.
- No telemetry/analytics.

---
*tech focus analysis: 2026-08-11*
<!-- refreshed: 2026-08-11 -->
