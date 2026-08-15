# scip-swift: Project Overview & PDR

## Problem Statement

The SCIP ecosystem (a standard code intelligence protocol used by Sourcegraph, codeintel, and editor plugins) has indexers for many languages — Python, Go, TypeScript, Java, Rust — but no official indexer exists for Swift. This gap means Swift developers cannot use modern code intelligence tooling for cross-reference navigation, symbol search, and documentation generation in the same way other language communities can.

## Goals

- **Primary**: Deliver a real SCIP indexer for Swift that produces genuine protobuf `Index`/`Document`/`Symbol`/`Occurrence` messages consumable by any standard SCIP tool.
- **Secondary**: Leverage existing SCIP infrastructure (the `scip` CLI, Sourcegraph, editor plugins) without requiring format translation or custom parsers.
- Enable Swift developers to use code intelligence tooling equivalent to what exists in other ecosystems.

## Non-Goals

- **Do not build a custom code navigation format.** Use the existing SCIP protobuf specification as-is.
- **Do not parse Swift source code.** Delegate to the compiler's own index (IndexStore), which powers Xcode and SourceKit-LSP.
- **Do not target Linux.** Indexing projects that import Apple-platform frameworks requires a macOS host with Xcode and SDKs.
- **Do not implement demangled symbol names.** Use raw USRs as-is; they are project-wide-unique and stable.

## Target Users

- **Sourcegraph users** running the `sourcegraph/scip` CLI or integrating with Sourcegraph Cloud.
- **Editor plugin consumers** (VS Code, JetBrains IDEs, etc.) using SCIP-based code intelligence extensions.
- **Swift developers** needing cross-repository symbol resolution and code navigation.
- **Tool builders** integrating SCIP into their documentation or code analysis pipelines.

## Success Criteria

- v0.1.0 shipped: ✅ Complete (tagged release, macOS arm64 binary via GitHub Releases)
- Produces valid protobuf `Index` messages that pass `scip lint` ✅
- Handles both SwiftPM and Xcode-based repos ✅
- Integrates with IndexStoreDB (the standard Swift compiler index) ✅
- Documented limitations and known behaviors ✅
- Open source (Apache-2.0) ✅

## Feature Set

- Automatic detection of build system (SwiftPM or Xcode projects).
- Configurable build tool, configuration (debug/release), and Xcode scheme selection.
- Full pipeline: detect build → build with indexing enabled → read IndexStore → convert to SCIP → write `.scip` file.
- Mapping of IndexStoreDB symbol information (kind, role) to SCIP protobuf enums.
- Approximate occurrence ranges based on symbol display names.
- Handling of both defined and referenced-but-undefined symbols (required by SCIP spec).

## Known Limitations

1. **Symbol identity, not demangled names** — SCIP symbols use raw compiler USRs, not human-readable chains.
2. **Approximate occurrence ranges** — end column estimated from symbol display-name length, not exact source-level ranges.
3. **No call-hierarchy role** — SCIP SymbolRole has no call-specific bit; calls are marked as references.
4. **USR stability depends on toolchain version** — Not guaranteed across Swift versions; this project pins `6.2.4`.

See [README.md](../README.md) for detailed limitations and platform requirements.

## Development Status

**Shipped**: v0.2.1 (current; see `Sources/scip-swift/Version.swift`). The initial tagged release was v0.1.0 (macOS arm64 binary via GitHub Releases); v0.1.1 and v0.1.2 were follow-up patch releases (notably the `index` subcommand and disabled code signing for index-only `xcodebuild` runs); v0.2.0 shipped the Homebrew formula, incremental indexing (`--cache-dir`), extended symbol metadata (signatures, relationships), and cross-repo merge (`index-many --merge`); v0.2.1 is the current patch release.

**Open items**:
- Exact range recovery (requires AST-level symbol location data)
- Demangled symbol names (requires Swift compiler's mangling library)
- Toolchain version compatibility testing
- Docstring extraction for extended symbol metadata (signatures and relationships shipped in v0.2.0)

## Technical Stack

- **Language**: Swift 6.2.4
- **Build System**: SwiftPM (Package.swift)
- **Key Dependencies**:
  - `swiftlang/indexstore-db` — IndexStore query API
  - `apple/swift-protobuf` — SCIP protobuf code generation
  - `apple/swift-argument-parser` — CLI argument handling
- **CI/CD**: GitHub Actions (macOS-26 runners)
- **Protobuf Source**: Upstream `sourcegraph/scip` (vendored at `Protos/scip.proto`)

## References

- Codebase Architecture: [docs/system-architecture.md](./system-architecture.md)
