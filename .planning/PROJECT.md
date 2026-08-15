# scip-swift

## What This Is

`scip-swift` is a CLI tool that converts a Swift repository's compiler index (IndexStoreDB) into a standard SCIP (Sourcegraph Code Intelligence Protocol) protobuf index. It bridges the gap between Swift's compiler-level symbol data and the broader code-intelligence ecosystem (Sourcegraph, editor plugins, documentation tools) that speaks SCIP — a gap no official Swift indexer previously filled.

## Core Value

Produce valid, `scip lint`-passing `.scip` indexes from any Swift repository (SwiftPM or Xcode-based) so Swift developers get the same cross-reference navigation, symbol search, and code intelligence that exists for Python, Go, TypeScript, and Rust.

## Requirements

### Validated

- ✓ Full build → IndexStore → SCIP protobuf pipeline — v0.1.0
- ✓ SwiftPM build backend with `--enable-index-store` — v0.1.0
- ✓ Xcode build backend with `COMPILER_INDEX_STORE_ENABLE=YES` — v0.1.0
- ✓ Automatic build system detection (`.xcworkspace` > `.xcodeproj` > `Package.swift`) — v0.1.0
- ✓ IndexStoreDB integration for compiler-level symbol data — v0.1.0
- ✓ Four pure-function mappers (symbol formatting, kind, role, position) — v0.1.0
- ✓ Protobuf serialization via SwiftProtobuf — v0.1.0
- ✓ `scip lint` passes on output — v0.1.0
- ✓ macOS arm64 binary via GitHub Releases — v0.1.0
- ✓ `index` subcommand as default (`scip-swift <repo>` works bare) — v0.1.1
- ✓ Disabled code signing for index-only xcodebuild runs — v0.1.2
- ✓ Symbol relationships (inheritance, conformance, override) mapped to SCIP — v0.2.0
- ✓ Enclosing symbols for locals via `.childOf` relation — v0.2.0
- ✓ Expanded role bits (Test, Generated, ForwardDefinition) — v0.2.0
- ✓ Basic signatures reconstructed from kind/subKind/displayName — v0.2.0
- ✓ Authoritative external-symbol classification via `SymbolLocation.isSystem` — v0.2.0
- ✓ Homebrew formula + release CI with universal binary — v0.2.0
- ✓ Incremental indexing with content-hash cache + version invalidation — v0.2.0
- ✓ `--cache-dir` and `--index-only` CLI flags — v0.2.0
- ✓ Cross-repo `index-many` subcommand with `--merge` — v0.2.0
- ✓ SCIP version field disambiguation for same-named modules — v0.2.0
- ✓ Xcode end-to-end integration test fixture — v0.2.0

### Active

- [ ] Demangle USRs into human-readable symbol names (e.g. `MiniSwift.greet(name:)` instead of `s:9MiniSwift5greetyySSF`) — v0.3.0
- [ ] Emit exact occurrence ranges (replace display-name-length end-column approximation) — v0.3.0
- [ ] Support `xcodebuild -destination` selection so iOS-only targets fully index — v0.3.0
- [ ] Emit symbol documentation (doc comments and markdown `documentation` field) — v0.3.0

### Out of Scope

- Linux support — `libIndexStore.dylib` and Apple SDKs are macOS-only; architectural, not a feature gap
- Source code parsing — the compiler's own IndexStore is the data source; no custom Swift parser
- Custom code navigation format — SCIP protobuf spec is used as-is
- Demangled symbol names — ~~deferred to v1.0+~~ now scoped for v0.3.0 (SwiftDemangler feasibility to be validated in research)

## Context

**Current state:** v0.2.0 shipped. The tool works end-to-end for both SwiftPM and Xcode projects: it builds a target repo with indexing enabled, reads the resulting IndexStore via IndexStoreDB, maps occurrences/symbols (with relationships, role bits, enclosing symbols, and signatures) to SCIP protobuf messages, and writes a `.scip` file. The emitted index passes `scip lint`. Incremental caching speeds re-indexing. Cross-repo `index-many` with `--merge` handles multi-repo codebases. 95 tests across 16 suites.

**Known gaps:**
- Symbol names use raw USRs (unreadable to humans, though correct) — demangling deferred to v1.0+
- Occurrence ranges approximate from display-name length — IndexStoreDB provides only an anchor point
- `xcodebuild` without `-destination` may not fully index iOS-only targets

**Peer comparison:** scip-typescript and scip-rust both emit human-readable symbol names and provide documentation. scip-swift now matches on relationships and role bits but still trails on readable symbol names (demangling pending).

**Codebase characteristics:** Single executable target (~6000 lines of hand-written Swift + 3190 lines generated protobuf). Five-stage pipeline architecture with stateless pure-function mappers. Swift Testing framework (not XCTest). 2-space indentation, enum-as-namespace pattern for mappers. 95 tests across 16 suites including real-build integration tests.

## Current Milestone: v0.3.0 Readable Indexes

**Goal:** Make scip-swift's output human-readable and precise — demangled symbol names, exact occurrence ranges, iOS destination support, and symbol documentation.

**Target features:**
- Demangle USRs into readable Swift symbol names
- Exact occurrence ranges (no display-name-length approximation)
- `xcodebuild -destination` selection for iOS-only targets
- Symbol documentation (doc comments → SCIP `documentation` fields)

## Constraints

- **Tech stack**: Swift 6.2.4, macOS 14+ — IndexStore access requires `libIndexStore.dylib` (macOS-only)
- **Dependencies**: `IndexStoreDB` (pinned to `swiftlang/indexstore-db` main branch), `swift-protobuf`, `swift-argument-parser`
- **Toolchain**: Pinned to 6.2.4 via `.swift-version` — USR stability is not guaranteed across versions
- **Compatibility**: Output must pass `scip lint` and be consumable by standard SCIP tools (Sourcegraph, editor plugins)
- **CI**: GitHub Actions on macOS-26 runner (provides Xcode 26 / Swift 6.2 toolchain)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use IndexStoreDB (compiler index), not source parsing | Compiler data is authoritative; same source as Xcode/SourceKit-LSP | ✓ Good — zero false positives |
| Raw USR as symbol identifier (no demangling) | USRs are compiler-guaranteed project-unique; demangling needs unavailable compiler library | ⚠️ Revisit — correct but hurts readability |
| Approximate occurrence ranges from display-name length | IndexStoreDB only provides a single anchor point, not a range | ⚠️ Revisit — drifts for compound names |
| Enum-as-namespace for stateless mappers | Signals "no instances"; compile-time safety on exhaustive switches | ✓ Good |
| `xcodebuild` without `-destination` | Forced iOS destination breaks macOS-app projects; generic "My Mac" avoids provisioning failures | ⚠️ Revisit — iOS targets may not fully index |
| Drop call-site role onto `.reference` | `scip.proto` has no `Call` bit; spec limitation | — Pending (unfixable in spec) |
| Content-hash caching for incremental indexing | Avoids reprocessing unchanged files; version-keyed invalidation | ✓ Good — 95 tests, byte-identical second-run output |
| Opaque USR-wrapped SCIP symbol strings (no demangling) | Compiler-guaranteed unique; avoids fragile demangling dependency | ✓ Good — correct and stable; readability deferred to v1.0+ |
| `indexOneRepo` extraction for cross-repo reuse | Single responsibility; IndexManyCommand delegates per-repo then merges | ✓ Good |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `$gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `$gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-08-15 after v0.2.0 milestone; v0.3.0 scoped*
