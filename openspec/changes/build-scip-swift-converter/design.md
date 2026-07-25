## Context

Swift has no SCIP indexer anywhere in the Sourcegraph or wider community ecosystem (confirmed present for TypeScript, Java, Python, Rust, C/C++, Go, PHP — absent for Swift). Apple's own toolchain provides a path around this gap: `swift build -index-store-path <path>` (SwiftPM) or `xcodebuild -index-store-path <path>` (Xcode-project apps) produces an IndexStore — the same index Xcode's own "jump to definition" and SourceKit-LSP use. The `swiftlang/indexstore-db` library (Apache-2.0, actively maintained by Apple) reads this IndexStore and exposes a `SymbolOccurrence` query API with definition/reference/call roles.

`indexstore-db` itself is confirmed buildable and runnable on Linux for pure Swift-package code — but real iOS/watchOS/widget-extension code (`import UIKit`/`WatchKit`/`WidgetKit`) cannot be compiled at all without Apple's iOS SDK, which Apple does not ship for Linux. Producing the raw IndexStore for an actual iOS app repo therefore requires a macOS build host regardless of which build command is used.

An adjacent project, `Fostonger/SwiftSCIPIndex`, was evaluated during discovery. It uses the same `swiftlang/indexstore-db` dependency and confirms it resolves and builds cleanly — a real, useful data point. But it is not a viable base: no `LICENSE` file (GitHub's license field is `null`, meaning all-rights-reserved by default — not legally forkable without the author's explicit permission), and its `Package.swift` has zero `SwiftProtobuf`/`scip.proto` dependency. Its output is a bespoke SQLite schema (`documents`/`symbols`/`relationships`/`occurrences` tables) that borrows SCIP's vocabulary but isn't wire-compatible with real `scip.proto` or any actual SCIP consumer.

## Goals / Non-Goals

**Goals:**
- Convert a Swift repo's build index into genuine `scip.proto`-conformant output — real protobuf messages, not a lookalike schema — consumable by any standard SCIP tool (the `scip` CLI, `codeintel`, Sourcegraph, editor plugins).
- Support both `swift build` and `xcodebuild` as the underlying build command, since real-world iOS app repos frequently don't build via SwiftPM.
- Keep the design consistent with how other SCIP indexers work: a standalone CLI, invoked as a subprocess, expected on `PATH` by whatever tool consumes it — not a library embedded in a specific consumer.

**Non-Goals:**
- Not designing a general-purpose SCIP-for-any-language framework — scoped to Swift only.
- Not solving Objective-C indexing — `scip-clang` already exists for that.
- Not making Apple-SDK-dependent code compilable on Linux — Apple does not distribute the iOS SDK for Linux; this is an accepted platform constraint, not something to design around. Only pure Swift-package code without Apple-platform-only imports can build on Linux.
- Not locking in the exact `Symbol.scip_symbol` mangling scheme in this document — see Open Questions.

## Decisions

**Decision 1 — Build around IndexStoreDB, not an alternative source of truth.**
Considered and rejected:
- *Fork/adapt `Fostonger/SwiftSCIPIndex`*: rejected — no license, and its output isn't real SCIP (see Context).
- *Drive SourceKit-LSP in batch mode and convert its responses to SCIP*: rejected — LSP is built for interactive, stateful use, not batch conversion; would require fragile process-lifecycle management for something meant to run once per index build.
- *Use `scip-clang` for the Objective-C-interop portions only*: rejected — clang cannot parse Swift at all, leaving the majority of a modern Swift codebase unindexed.
- **Chosen**: read `swiftlang/indexstore-db` directly (same engine as Xcode itself — highest-fidelity option available), emit real `scip.proto` via `SwiftProtobuf`.

**Decision 2 — Support both `swift build` and `xcodebuild` as the build-command backend.**
Real-world iOS-style repos may not build via SwiftPM at all. Accept an explicit build-command flag (or auto-detect — see Open Questions) rather than assuming `swift build` universally works.

**Decision 3 — IndexStoreDB → SCIP concept mapping:**

| IndexStoreDB | SCIP |
|---|---|
| `Symbol.name` | `Symbol.display_name` |
| `Symbol.usr` | `Symbol.scip_symbol` (mangling scheme — TBD, see Open Questions) |
| occurrence role `.definition` | `Occurrence.symbol_roles: Definition` |
| occurrence role `.reference` | `Occurrence.symbol_roles: ReadAccess` |
| occurrence role `.call` | `Occurrence.symbol_roles: ForwardCall` |
| `Symbol.kind` | SCIP `Symbol.kind` enum |
| `SymbolOccurrence.location` | `Occurrence.range` |

**Decision 4 — Distribute as a compiled binary release, not "clone and `swift build`."**
Consumers (e.g. `codeintel`) expect language indexers to be installable on `PATH` without needing the language's own toolchain (nobody installs a JDK to use `scip-java`). Ship prebuilt macOS binaries via GitHub Releases (and/or Homebrew) so a Python-only or Node-only consumer project never needs the Swift toolchain just to call this CLI.

**Decision 5 — Pin the Swift toolchain version used to build/run the converter.**
Swift's USR format is compiler-version-sensitive. Pinning avoids silent symbol-correlation breakage across toolchain upgrades — the same version-pinning discipline any serious SCIP tooling already applies to its protobuf schema.

## Risks / Trade-offs

- **[Risk]** Swift's USR format may change between compiler versions, silently breaking symbol correlation. **[Mitigation]** Pin the Swift toolchain version (Decision 5); track upstream compiler changelogs for USR-format notes.
- **[Risk]** Some real iOS projects only build via `xcodebuild`, not `swift build`. **[Mitigation]** Support both explicitly (Decision 2).
- **[Risk]** iOS/watchOS/widget-extension code cannot be compiled on Linux at all — a hard Apple platform constraint, not something this tool can work around. **[Mitigation]** Document the macOS-host requirement prominently; publish macOS-only prebuilt binaries.
- **[Risk]** Operational cost of a macOS build host for CI/release (self-hosted Mac mini vs. cloud Mac CI runner), plus the Swift toolchain's footprint (~1.2GB). **[Mitigation]** Accept as a documented cost of supporting Swift at all.
- **[Risk]** `Symbol.scip_symbol` mangling scheme is unspecified pending implementation. **[Mitigation]** Explicit open question below; resolve early since every downstream mapping depends on it.
- **[Risk]** If Sourcegraph or the SCIP community later ships an official `scip-swift`, this project becomes redundant maintenance. **[Mitigation]** Accept as a future deprecation trigger, not a reason to delay now — and note the naming overlap is a branding risk, not a technical collision (GitHub scopes repos by owner).

## Migration Plan

1. Validate `swiftlang/indexstore-db` resolves and builds against a real Swift repo (already derisked — confirmed via `Fostonger/SwiftSCIPIndex`'s `Package.swift`).
2. Implement the IndexStoreDB → SCIP protobuf mapping (Decision 3), resolving the USR mangling scheme as the first concrete task.
3. Implement both build-command backends (`swift build`, `xcodebuild`) behind a common interface.
4. Validate output against the `scip` CLI's own validation/inspection tooling, and against a real downstream consumer (`codeintel`'s `scip expt-convert` step) end-to-end.
5. Publish a tagged release with a prebuilt macOS binary.
6. No rollback concerns — this is a new, standalone project; nothing else depends on it yet.

## Open Questions

- What exact string-mangling scheme should `Symbol.scip_symbol` use to encode a Swift USR?
- Should the CLI auto-detect SwiftPM vs. Xcode-project repos, or require an explicit build-command flag from the caller?
- What's the concrete macOS build-host setup for CI/releases — self-hosted Mac mini, a cloud Mac CI runner (GitHub Actions macOS runners, MacStadium), or manual releases from a developer machine? (Infra decision, not a code-architecture one.)
