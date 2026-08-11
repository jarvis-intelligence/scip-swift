---
title: STACK
focus: tech
last_mapped_commit: 34a8c1e
---

# STACK

**Analysis Date:** 2026-08-11

Technologies, runtime, frameworks, dependencies, and build configuration for `scip-swift`.

## Summary

`scip-swift` is a **macOS-only Swift command-line tool** that converts a Swift repo's compiler
index (IndexStore) into a real `scip.proto` SCIP index. It is a single SwiftPM executable target
built against the Swift 6.2 toolchain.

- **Language:** Swift 6.2 (`Package.swift` declares `swift-tools-version: 6.2`)
- **Pinned toolchain:** `6.2.4` (`.swift-version`)
- **Platforms:** macOS 13+ (`platforms: [.macOS(.v14)]` in `Package.swift`); host runtime is macOS-only
- **Output artifact:** compiled `scip-swift` executable; output payload is a `.scip` protobuf file
- **Version:** `0.1.2` (`Sources/scip-swift/Version.swift`)

## Languages & Runtime

- **Swift** is the only source language. Swift 6.2 concurrency is enabled via the tools-version.
- `Sources/scip-swift/Generated/Scip.pb.swift` is a large (~3190 lines) **generated** file from the
  vendored `Protos/scip.proto` — never hand-edited; regenerate via `Protos/generate.sh`.
- A single executable target, `scip-swift`, plus a test target `scip-swiftTests` (`Package.swift`).

## Dependencies

Declared in `Package.swift`, pinned in `Package.resolved`:

- **indexstore-db** (`https://github.com/swiftlang/indexstore-db.git`, branch `main`, rev `c993f4fb`)
  — the core dependency. Provides `IndexStoreDB`, `Symbol`, `SymbolOccurrence`, `SymbolRole`,
  `SymbolLocation` types used to read the compiler's index. Transitive: pulls in **swift-lmdb**.
- **swift-protobuf** (`https://github.com/apple/swift-protobuf.git`, `1.28.0` → resolved `1.38.1`)
  — protobuf runtime + the generator that produces `Generated/Scip.pb.swift`.
- **swift-argument-parser** (`https://github.com/apple/swift-argument-parser.git`, `1.5.1` →
  resolved `1.8.2`) — CLI parsing (`ParsableCommand`, `@Argument`, `@Option`).

## Configuration

- `Package.swift` — SwiftPM manifest; one `.executable` product, one executable target, one test target.
- `.swift-version` — pins the toolchain to `6.2.4` (USR stability is toolchain-sensitive; see
  `ToolchainInfo.pinnedSwiftVersion`).
- `Package.resolved` — locked dependency revisions.
- `.gitignore` — ignores `.build/`, `.swiftpm/`, `*.scip`, and explicitly re-includes
  `Sources/scip-swift/Build/` (the user's global gitignore bare-`build` pattern would otherwise
  match it case-insensitively).
- No `.env`, no runtime config files — all configuration is via CLI flags at invocation.

## Build Commands

```sh
swift build                       # debug build
swift build -c release            # release build -> .build/release/scip-swift
swift test                        # all tests (unit + integration)
swift test --filter <SuiteName>   # one Swift Testing suite
Protos/generate.sh                # regenerate protobuf bindings (requires protoc + protoc-gen-swift)
```

Prerequisite: a Swift 6.2 toolchain + Xcode (for the iOS/macOS SDKs and `libIndexStore.dylib`).
`brew install protobuf swift-protobuf` is required only when regenerating the proto bindings.

## Generated vs Authored Code

| Kind | Location | Regen? |
|---|---|---|
| Authored Swift | `Sources/scip-swift/**` (excl. `Generated/`) | n/a |
| Generated protobuf bindings | `Sources/scip-swift/Generated/Scip.pb.swift` | `Protos/generate.sh` |
| Vendored proto schema | `Protos/scip.proto` (from `sourcegraph/scip`) | upstream sync |
| Tests | `Tests/scip-swiftTests/*.swift` | n/a |
| Fixture repo | `Fixtures/MiniSwiftPackage/` | n/a |

## Distribution

Compiled binary release (GitHub Releases, macOS arm64). Homebrew formula is an open roadmap item
(`docs/project-roadmap.md`). Not a library package — no `.library` product is exported.

---
*tech focus analysis: 2026-08-11*
<!-- refreshed: 2026-08-11 -->
