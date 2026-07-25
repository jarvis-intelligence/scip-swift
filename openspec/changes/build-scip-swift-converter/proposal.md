## Why

No SCIP indexer exists for Swift anywhere in the Sourcegraph or wider SCIP ecosystem (confirmed present for TypeScript, Python, Java, Rust, C/C++, Go, PHP — absent for Swift). Swift codebases therefore can't get semantic navigation (go-to-definition, find-references, call/type hierarchy) from any SCIP-consuming tool — only lexical search. Apple's own toolchain already produces a high-fidelity symbol index for this purpose (IndexStoreDB, the same engine behind Xcode's own "jump to definition" and SourceKit-LSP), so building a converter is largely integration work, not inventing a new symbol-resolution scheme.

An existing project (`Fostonger/SwiftSCIPIndex`) was evaluated as a possible starting point and rejected: it carries no license (all-rights-reserved by default, not legally forkable) and emits a bespoke SQLite schema with no `SwiftProtobuf`/`scip.proto` dependency anywhere — SCIP-inspired in naming only, not wire-compatible with real SCIP output or any actual SCIP consumer. Its one useful signal: its `Package.swift` confirms `swiftlang/indexstore-db` resolves and builds cleanly as a dependency, derisking that part of this approach.

## What Changes

- New standalone CLI, `scip-swift`, that converts a Swift repo's build index into genuine `scip.proto` output (real protobuf messages, not a lookalike schema).
- Pipeline: run `swift build -index-store-path <path>` (SwiftPM) or `xcodebuild -index-store-path <path>` (Xcode-project apps) → read the resulting IndexStore via `swiftlang/indexstore-db`'s `SymbolOccurrence` query API → map to SCIP `Document`/`Symbol`/`Occurrence` messages via `SwiftProtobuf` → emit a `.scip` (or SQLite-via-`scip expt-convert`-compatible) index.
- Support both `swift build` and `xcodebuild` as the underlying build command, since real iOS/watchOS/widget-extension repos frequently don't build via SwiftPM at all.
- Pin the Swift toolchain version used to build/run the converter, matching the version-pinning discipline any serious SCIP tooling already applies to its protobuf schema.

## Capabilities

### New Capabilities
- `swift-indexstore-to-scip`: Detecting a Swift repo's build system (SwiftPM vs. Xcode project), producing an IndexStore via the appropriate build command, and converting its contents into real `scip.proto`-conformant output consumable by any standard SCIP tool (`scip` CLI, `codeintel`, Sourcegraph, editor plugins).

### Modified Capabilities
- None — this is the first change in a new repo; no existing specs to modify.

## Impact

- **New repo**: this is a standalone project, published for general use — not vendored into any single consumer (e.g. `codeintel`, which only ever invokes language indexers as external `PATH` binaries and never bundles their source).
- **New external dependencies**: `swiftlang/indexstore-db` (Apache-2.0, Apple-maintained) for reading the IndexStore; `SwiftProtobuf` + a `scip.proto`-generated Swift module for emitting real SCIP.
- **Host requirement**: building and running `scip-swift` against any repo that imports Apple-platform-only frameworks (`UIKit`/`WatchKit`/`WidgetKit`) requires a macOS host with Xcode and the relevant SDKs — Apple does not ship the iOS SDK for Linux. Pure Swift-package code without those imports can build on Linux, but that's not the common case for a real iOS app repo.
- **Toolchain footprint**: the Swift toolchain needed is heavier (~1.2GB) than typical scripting-language SCIP indexers — a documented cost, not a blocker.
- **No breaking changes**: nothing exists yet for this to break.
