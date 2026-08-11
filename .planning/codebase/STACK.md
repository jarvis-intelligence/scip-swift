# Technology Stack

**Analysis Date:** 2026-08-11

## Languages

**Primary:**
- Swift 6.2 (`swift-tools-version: 6.2` in `Package.swift:1`) — the entire tool is Swift. All sources under `Sources/scip-swift/`.

**Secondary:**
- Protobuf (`.proto`) — `Protos/scip.proto` is the vendored SCIP schema; compiled to Swift via `protoc-gen-swift` into `Sources/scip-swift/Generated/Scip.pb.swift`.
- Bash — `Protos/generate.sh` regenerates the protobuf bindings.

**Pinned toolchain:**
- Swift 6.2.4 — `.swift-version:1` and mirrored as `ToolchainInfo.pinnedSwiftVersion` in `Sources/scip-swift/Platform/ToolchainInfo.swift:8`. Apple does not guarantee USR (symbol-identity) stability across toolchain versions, so this pin is load-bearing.

## Runtime

**Environment:**
- macOS 14+ — `Package.swift:6` declares `.macOS(.v14)`. macOS-only by necessity: IndexStore access requires `libIndexStore.dylib` (ships only in the Xcode toolchain), and indexing repos that import `UIKit`/`WatchKit`/`WidgetKit` needs the Apple SDKs, which are macOS-only.
- The built executable (`scip-swift`) itself runs on macOS. It is not a library; it is an executable product (`Package.swift:8`).

**Package Manager:**
- Swift Package Manager (SwiftPM) — declared in `Package.swift`.
- Lockfile: `Package.resolved` (present, version 3 format).

## Frameworks

**Core:**
- SwiftPM toolchain (`swift-tools-version: 6.2`) — build/package management.
- `swift-argument-parser` 1.8.2 (pinned) / `from: "1.5.1"` (`Package.swift:11`) — CLI argument parsing. `ScipSwiftCommand` (`Sources/scip-swift/ScipSwiftCommand.swift`) is the `@main` root; `IndexCommand` (`Sources/scip-swift/Commands/IndexCommand.swift`) is the sole/default subcommand.

**Indexing library (the central dependency):**
- `IndexStoreDB` — the Swift API over Apple's IndexStore format (`Package.swift:8-9`, `Package.swift:18`). Pinned to `branch: "main"` of `swiftlang/indexstore-db` (revision `c993f4fb...` per `Package.resolved`). This is the same index that powers Xcode's "jump to definition" and SourceKit-LSP. Loaded at runtime in `Sources/scip-swift/IndexStore/IndexStoreLoader.swift`.

**Serialization:**
- `swift-protobuf` 1.38.1 (pinned) / `from: "1.28.0"` (`Package.swift:10`) — runtime for the generated `Scip.pb.swift`. Used via `index.serializedData()` in `Sources/scip-swift/Commands/IndexCommand.swift:43`.

**Testing:**
- Swift Testing (`@Suite` / `@Test` / `#expect` / `#require`) — not XCTest. Test sources in `Tests/scip-swiftTests/`. Integration tests shell out to real `swift build` against `Fixtures/MiniSwiftPackage` (no mocks).

**Build/Dev:**
- `swift build` / `swift test` — the standard SwiftPM CLI.
- `protoc` + `protoc-gen-swift` — only needed when regenerating bindings (`Protos/generate.sh`); installed via `brew install protobuf swift-protobuf`.

## Key Dependencies

**Critical:**
- `indexstore-db` (SwiftPM package `indexstore-db`, product `IndexStoreDB`) — the entire pipeline reads symbol occurrences from here. `IndexStoreLoader.open(storePath:databasePath:)` (`Sources/scip-swift/IndexStore/IndexStoreLoader.swift:7`) loads it against a `libIndexStore.dylib` path resolved via `xcrun --find swift` (`Sources/scip-swift/Platform/ToolchainInfo.swift:16`).
- `swift-protobuf` (product `SwiftProtobuf`) — emits the `.scip` file via generated message types (`Scip_Index`, `Scip_Document`, `Scip_Occurrence`, `Scip_SymbolInformation`, `Scip_Metadata`, `Scip_ToolInfo`).
- `swift-argument-parser` (product `ArgumentParser`) — defines the CLI surface (`--output`, `--build-tool`, `--configuration`, `--scheme`, `--version`).

**Transitive (resolved, not declared directly):**
- `swift-lmdb` (from `swiftlang/swift-lmdb`, branch `main`, revision `a4bc8780...`) — brought in by `indexstore-db` for its LMDB-backed index database. Appears in `Package.resolved` only.

**Vendored (not a SwiftPM dependency):**
- `Protos/scip.proto` and `Sources/scip-swift/Generated/Scip.pb.swift` — the SCIP schema and generated Swift bindings, vendored from upstream `sourcegraph/scip`. **Never hand-edit `Generated/Scip.pb.swift`**; regenerate via `Protos/generate.sh`.

## Configuration

**Environment:**
- No `.env` files, no runtime configuration files. The tool is configured entirely through CLI flags (`Sources/scip-swift/Commands/IndexCommand.swift:7-22`):
  - `repoPath` (positional, defaults to CWD)
  - `--output <path>` (default: `<repo>/index.scip`)
  - `--build-tool swiftpm|xcodebuild` (auto-detected if omitted)
  - `--configuration debug|release` (default: `debug`)
  - `--scheme <name>` (xcodebuild only; auto-detected if exactly one scheme exists)
  - `--version`

**Toolchain resolution (runtime):**
- `xcrun --find swift` locates the active toolchain, then `libIndexStore.dylib` is resolved relative to it at `<toolchain>/usr/lib/libIndexStore.dylib` (`Sources/scip-swift/Platform/ToolchainInfo.swift:16-33`). `SubprocessRunner.resolveExecutable(named:)` (`Sources/scip-swift/Build/SubprocessRunner.swift:69`) uses `/usr/bin/env which` for PATH lookup of `swift`/`xcodebuild`/`xcrun`.

**Build config:**
- `Package.swift` — single executable target `scip-swift` + test target `scip-swiftTests`.
- `.swift-version` — pins the toolchain for contributors and CI.
- `.gitignore` — present (build artifacts, `.build`, `DerivedData`, etc.).
- No lint/format config files (`.swiftformat`, `.swiftlint.yml`, `.editorconfig`) — not present.

## Platform Requirements

**Development:**
- macOS 14+ with Xcode and the Swift 6.2.4 toolchain.
- `protoc` / `protoc-gen-swift` only if regenerating protobuf bindings.
- CI runs on `macos-26` (`.github/workflows/ci.yml:13`) to get Xcode 26 (provides the Swift 6.2 toolchain).

**Production:**
- The tool ships as a compiled macOS executable (`README.md` documents `swift build -c release` then `cp .build/release/scip-swift /usr/local/bin/`). Distributed as a binary release per the PDR (Version 0.1.2 — `Sources/scip-swift/Version.swift:4`).
- **Deliberately not Linux-compatible**: `libIndexStore.dylib` is macOS-only and Apple-platform SDKs are required for real-world iOS/watchOS repos. Do not attempt to make the build/test pipeline pass on Linux (`.github/workflows/ci.yml` is macOS-only by design).

---

*Stack analysis: 2026-08-11*
