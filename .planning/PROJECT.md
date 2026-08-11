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

### Active

- [ ] Homebrew formula for easy installation (`brew install`)
- [ ] Incremental indexing — cache IndexStore results, only reprocess changed files
- [ ] Symbol metadata enrichment — relationships, role bits, enclosing symbols, signatures
- [ ] Cross-repo symbol linking — multi-repo indexing mode resolving cross-references

### Out of Scope

- Linux support — `libIndexStore.dylib` and Apple SDKs are macOS-only; architectural, not a feature gap
- Source code parsing — the compiler's own IndexStore is the data source; no custom Swift parser
- Custom code navigation format — SCIP protobuf spec is used as-is
- Demangled symbol names in v0.2.0 — deferred to v1.0+; needs compiler mangling library or custom demangler (H2 2027)

## Context

**Current state:** v0.1.2 shipped. The tool works end-to-end: it builds a target repo with indexing enabled, reads the resulting IndexStore via IndexStoreDB, maps occurrences/symbols to SCIP protobuf messages, and writes a `.scip` file. The emitted index passes `scip lint` and is consumed by Sourcegraph and other SCIP tools.

**Known gaps (from `docs/research-scip-swift-limitations.md`):**
- Relationships (inheritance, conformance, override) are fetched from the compiler but silently discarded — the highest-impact missing feature
- Symbol names use raw USRs (unreadable to humans, though correct)
- SymbolRole mapping drops several IndexStoreDB roles that have SCIP equivalents
- No documentation or signature data in symbol information
- Xcode path has no end-to-end integration test fixture

**Peer comparison:** scip-typescript and scip-rust both emit human-readable symbol names, populate relationships, and provide documentation. scip-swift matches on data source (compiler index) but trails on these three areas.

**Codebase characteristics:** Single executable target (~1200 lines of hand-written Swift + 3190 lines generated protobuf). Five-stage pipeline architecture with stateless pure-function mappers. Swift Testing framework (not XCTest). 2-space indentation, enum-as-namespace pattern for mappers.

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
*Last updated: 2026-08-11 after initialization*
