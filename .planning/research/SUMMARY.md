# Project Research Summary

**Project:** scip-swift v0.2.0
**Domain:** Swift compiler-index → SCIP protobuf CLI indexer
**Researched:** 2026-08-11
**Confidence:** HIGH

## Executive Summary

scip-swift is a macOS-only CLI tool that converts a Swift repo's compiler index (IndexStoreDB) into a standard `scip.proto` SCIP index. It already delivers a working five-stage pipeline (CLI → build orchestration → index access → SCIP mapping → protobuf output) that passes `scip lint`. The v0.2.0 effort targets the parity gaps between scip-swift and peer indexers (scip-typescript, rust-analyzer/scip-rust, scip-python), plus distribution and performance improvements. The headline finding: **no new dependencies are required** — all four feature areas (metadata enrichment, Homebrew distribution, incremental indexing, multi-repo linking) are implementable using APIs already present in the pinned IndexStoreDB revision and existing SwiftProtobuf/ArgumentParser packages.

The recommended approach is **enrichment-first**. The highest-impact gap is that IndexStoreDB's `occurrence.relations` array — which carries inheritance, conformance, override, and enclosing-scope data — is fetched from the compiler and silently discarded. Mapping these to SCIP `Relationship` and `enclosing_symbol` fields unlocks "Find implementations," inheritance hierarchy navigation, and protocol conformance links with zero new dependencies. This enrichment work must be completed and stable before incremental indexing is layered on, because cached `Scip_Document` protobuf messages must already contain relationships/signatures when written — otherwise the first enrichment improvement invalidates every cache entry. Homebrew distribution (custom tap with pre-built binary) and the Xcode end-to-end test fixture are fully independent of the mapping work and can ship in parallel.

The key risks are threefold. First, **IndexStoreDB relation population depth for Swift is empirically unverified** — the API exists (confirmed by source), but whether the Swift compiler populates `.baseOf`/`.overrideOf`/`.extendedBy` as richly as Clang must be validated before committing to the relationship mapping design. Second, **incremental cache invalidation is the riskiest feature** — stale cache data silently serves incorrect occurrence data, and USR instability across toolchain versions complicates cache key design. Third, **the Homebrew binary depends on `libIndexStore.dylib`** which ships only with Xcode (not CommandLineTools), requiring a runtime check with a clear error message. Mitigation for all three is well-documented in the research: validate relations empirically in the enrichment phase, include `.swift-version` in cache keys, and add a dylib-resolution guard to the CLI.

## Key Findings

### Recommended Stack

The existing stack (Swift 6.2.4, IndexStoreDB @ `c993f4fb`, SwiftProtobuf 1.38.1, ArgumentParser 1.8.2) requires **zero version changes** for v0.2.0. All feature work uses APIs already exposed by these packages. The only new infrastructure is a Homebrew custom tap for distribution — `homebrew/core` is architecturally blocked (all formulae must build on Linux; `libIndexStore.dylib` is macOS-only).

**Core technologies (unchanged, already in use):**
- **IndexStoreDB** (`indexstore-db` @ `c993f4fb`) — compiler index data source; relations API, `dateOfLatestUnitFor`, `pollForUnitChangesAndWait` all present and verified
- **SwiftProtobuf** (1.38.1) — SCIP protobuf serialization; supports everything needed including external index parsing for cross-repo resolution
- **swift-argument-parser** (1.8.2) — CLI framework; supports new `--cache-dir`, `--incremental`, `--link` flags without version change

**New infrastructure (no runtime dependency):**
- **Homebrew custom tap** (`phuongddx/homebrew-scip-swift`) — only viable distribution path for macOS-only Swift tool; pre-built binary formula, no build-from-source
- **GitHub Actions release workflow** — automate tarball upload + formula SHA256 update on tag push

**Explicitly avoided:**
- SwiftSyntax (heavyweight; basic signatures reconstructible from IndexStoreDB `kind`/`name`)
- Custom USR demangler (needs compiler mangling library; deferred to v1.0+)
- Source-file parser (IndexStoreDB is authoritative; no false-positive drift)

### Expected Features

**Must have for v0.2.0 (table stakes / parity gaps):**
- **Relationships** (inheritance, conformance, override) — highest-impact gap; enables "Find implementations." Data already fetched from IndexStoreDB, just needs mapping. Requires empirical validation of Swift relation depth.
- **`enclosing_symbol` for locals** — free byproduct of relationships work (`.childOf` relation). Populates symbol hierarchy.
- **Expanded SymbolRole bits** — `Test`, `Generated`, `ForwardDefinition`. Easiest win; pure-function mapper additions.
- **Signature documentation** — basic signatures (`func greet`, `var name`) reconstructible from IndexStoreDB `kind`/`name`. Improves hover tooltips.
- **Xcode end-to-end test fixture** — closes last test-coverage gap; prevents silent regressions for Xcode-only projects.
- **`isSystem`-based external symbol classification** — swap heuristic for authoritative `SymbolLocation.isSystem` flag. Correctness improvement.

**Should have (differentiators, add after validation):**
- **Source-comment docstring extraction** — unique win; requires new source-file reading infrastructure (also enables `enclosing_range`)
- **Index-only mode** (`--no-build`) — read existing IndexStore, skip build; cheaper than full incremental for CI reuse
- **typed_range adoption** — forward-looking SCIP 0.4+ encoding; pure mapping change
- **Xcode `-destination` auto-resolution** — improves iOS target coverage; needs scheme parsing research

**Defer to v1.0+ (anti-features):**
- **Demangled symbol names** — 20+ hours, compiler-library dependency; correctness unaffected (`displayName` covers rendering)
- **Cross-run incremental caching** — no peer indexer does this; architecturally complex. Let the compiler handle incrementalism via persistent scratch path instead.
- **Linux support** — architectural blocker (`libIndexStore.dylib` is macOS-only)
- **Streaming protobuf serialization** — premature optimization; only relevant for 100k+ file repos
- **Call hierarchy (`Call` role)** — unfixable in SCIP spec (no `Call` bit exists)

### Architecture Approach

The existing five-stage pipeline (CLI → Build Orchestration → Index Access → SCIP Mapping → Output) remains the backbone. v0.2.0 enriches existing stages rather than restructuring them. All mapping enrichment (relationships, signatures, roles, enclosing symbols) modifies a single method: `SCIPIndexBuilder.makeDocument()`. Incremental indexing introduces a new Cache layer (`CacheStore`, `ChangeDetector`, `IndexManifest`) that sits between Build Orchestration and SCIP Mapping, breaking the current stateless invariant — the largest architectural shift. Multi-repo indexing adds a new `index-many` subcommand and `MultiRepoMerger` component that operates on pure protobuf (no IndexStoreDB dependency). Homebrew distribution is pure infrastructure (CI + formula), touching no application code.

**Major v0.2.0 components (new):**
1. **`RelationshipMapping`** — maps IndexStoreDB `SymbolRelation` → SCIP `Relationship` (`.baseOf`/`.extendedBy` → `is_implementation`, `.overrideOf` → `is_reference`)
2. **`SignatureMapping`** — reconstructs minimal Swift signatures from `Symbol.kind`/`name`
3. **`CacheStore` + `ChangeDetector` + `IndexManifest`** — document-level cache with SHA-256 content hashing and toolchain-version invalidation
4. **`MultiRepoMerger`** — deduplicates symbols, recomputes `external_symbols`, prefixes document paths across repos

### Critical Pitfalls

1. **Relationships silently dropped** (Pitfall 1) — `occurrence.relations` is fetched and discarded. Result: "Find implementations" returns nothing. Fix: read relations in `makeDocument()`, map to `Scip_Relationship`. **Validate Swift relation depth empirically before committing to design.**

2. **Relationship booleans set incorrectly** (Pitfall 2) — wrong `is_reference`/`is_implementation` flags break "Find References" or "Find Implementations." Protocol conformance = `is_implementation` only; method override = `is_reference` only. Every `Relationship.symbol` must exist in the index or `scip lint` errors. Fix: explicit mapping table validated against proto's TypeScript example.

3. **Stale incremental cache serves bad data** (Pitfall 3) — IndexStoreDB database reused without polling for changes, or partial build produces incomplete store. Fix: always open fresh with `waitUntilDoneInitializing: true`, use `dateOfLatestUnitFor(filePath:)` for staleness, validate build exit code 0, include toolchain version in cache key.

4. **Multi-repo symbol collision** (Pitfall 4) — same module name in different repos produces identical SCIP symbol strings; different toolchain versions produce different USRs. Fix: require same toolchain across repos, populate `version` field in symbol format, run `scip lint` on merged index.

5. **Homebrew binary crashes — dylib not found** (Pitfall 5) — `libIndexStore.dylib` ships only with Xcode, not CommandLineTools, and cannot be a Homebrew dependency. Fix: runtime check with clear error message; document Xcode requirement prominently.

## Implications for Roadmap

Based on combined research, the following phase structure is recommended. The ordering is driven by a hard dependency: **enrichment must be stable before caching**, because cached documents must already contain relationships/signatures.

### Phase 1: Symbol Metadata Enrichment
**Rationale:** Highest-impact, lowest-risk work. The data already exists in IndexStoreDB — this phase reads what's already fetched. Establishes the pattern for all future mapper extensions. Must complete before incremental indexing (Phase 4) so cached documents are complete.
**Delivers:** Relationships (Find implementations), `enclosing_symbol`, expanded SymbolRole bits, basic signatures, `isSystem` external symbol classification
**Addresses:** All P1 table-stakes features from FEATURES.md
**Avoids:** Pitfall 1 (relationships dropped), Pitfall 2 (wrong booleans), Pitfall 6 (misclassified external symbols)
**Scope:** `RelationshipMapping` (new), `SignatureMapping` (new), `SymbolRoleMapping` (extended), `SCIPIndexBuilder.makeDocument()` (modified), `PositionMapping` (minor)

### Phase 2: Xcode End-to-End Test Fixture
**Rationale:** Independent test infrastructure; can be developed in parallel with Phase 1. Closes the last coverage gap — Xcode build path is currently validated by argument assertions only, not a real build.
**Delivers:** Minimal `.xcodeproj` fixture + CI step that builds and indexes it end-to-end
**Addresses:** Xcode fixture from FEATURES.md table stakes
**Avoids:** Silent regression in `XcodebuildBuildRunner` that breaks Xcode-only projects

### Phase 3: Homebrew Distribution & Release Pipeline
**Rationale:** Fully independent of mapping changes — pure infrastructure. Enables user adoption. Ship as soon as ready.
**Delivers:** Custom tap (`phuongddx/homebrew-scip-swift`), GitHub Actions release workflow, universal binary (arm64 + x86_64), formula with sha256 automation
**Addresses:** Distribution — no direct feature dependency, but unblocks `brew install scip-swift`
**Avoids:** Pitfall 5 (dylib not found) — runtime check + clear error message built into this phase

### Phase 4: Incremental Indexing
**Rationale:** Largest architectural change (breaks stateless invariant). Must come after Phase 1 — cached documents must already contain relationships/signatures, otherwise the next enrichment improvement invalidates all caches. Also depends on stable mapping output format.
**Delivers:** `CacheStore`, `ChangeDetector`, `IndexManifest`, `--cache-dir`/`--incremental` flags, persistent scratch path for SwiftPM incremental builds, document-level cache with SHA-256 hashing
**Addresses:** Build-time bottleneck for repos >100 files; performance differentiator
**Avoids:** Pitfall 3 (stale cache) — staleness checks, toolchain-version cache key, build exit-code validation
**Research flag:** Cache invalidation strategy needs validation during planning — IndexStoreDB lifecycle semantics (`pollForUnitChangesAndWait`, `dateOfLatestUnitFor`) are well-documented but the end-to-end cache correctness flow must be tested empirically.

### Phase 5: Multi-Repo Indexing (Optional)
**Rationale:** Depends on Phase 1 (relationships needed for cross-repo linking value) and Phase 4 (incremental benefits multi-repo builds). Highest complexity, lowest marginal value — SCIP spec handles cross-repo resolution at consumer level (Sourcegraph). Consider deferring to v0.3.0 unless monorepo use case demands it.
**Delivers:** `index-many` subcommand, `MultiRepoMerger`, `--merge-output` flag, `--no-external-symbols` flag
**Addresses:** Cross-repo linking for monorepo / multi-package scenarios
**Avoids:** Pitfall 4 (symbol collision) — version field population, toolchain validation, `scip lint` on merged index

### Phase Ordering Rationale

- **Enrichment before caching (Phase 1 → Phase 4):** Cached `Scip_Document` messages must contain relationships/signatures when written. If caching ships first, every enrichment improvement invalidates all cache entries — zero benefit.
- **SymbolRole extension first within Phase 1:** Zero-risk, zero-dependency. Establishes the pattern for extending existing mappers. Immediate value (tags test symbols).
- **Homebrew and Xcode fixture in parallel (Phases 2+3):** Both are fully independent of mapping code. Ship as soon as ready.
- **Incremental after enrichment (Phase 4):** The stateless invariant is the hardest thing to break correctly. Only worth breaking once the output format is stable.
- **Multi-repo last (Phase 5):** Depends on both relationships and incremental. SCIP spec already handles cross-repo at consumer level, so this is a marginal-value feature.

### Research Flags

Phases likely needing deeper research during planning (`/gsd-plan-phase --research-phase`):
- **Phase 1 (Enrichment):** Must empirically validate that the Swift compiler populates `occurrence.relations` with the same depth as Clang. The API exists (verified from source), but Swift-specific relation population is unconfirmed. This is the single biggest unknown in the roadmap.
- **Phase 4 (Incremental):** IndexStoreDB lifecycle semantics are documented but the end-to-end cache correctness flow (fresh open → staleness check → poll → query) needs integration testing. USR stability across toolchain versions must be documented as a cache invalidation policy.

Phases with standard patterns (skip research-phase):
- **Phase 2 (Xcode fixture):** Standard test infrastructure — create minimal `.xcodeproj`, add CI step.
- **Phase 3 (Homebrew):** Well-documented patterns — custom tap, pre-built binary formula, GitHub Actions release workflow. Formula Cookbook provides exact templates.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All APIs verified against checked-out IndexStoreDB source. No dependency changes needed — confirmed from `Package.swift` + `Package.resolved`. Homebrew approach verified against official docs + real formulae. |
| Features | HIGH | Gap analysis grounded in source code of all three peer indexers + canonical `scip.proto` + `scip lint` Go source. Feature prioritization matrix validated against competitor analysis. |
| Architecture | HIGH | Current architecture mapped from actual codebase. Target architecture follows existing patterns (enum-as-namespace mappers, exhaustive switches, single executable target). Anti-patterns identified and documented. |
| Pitfalls | HIGH | All 6 critical pitfalls verified against primary sources (`scip.proto`, `scip lint` Go source, IndexStoreDB Swift API). Recovery strategies and phase mappings defined. |

**Overall confidence:** HIGH — research is grounded in primary sources (actual IndexStoreDB source code, canonical SCIP proto, official Homebrew docs, peer indexer source code). The main uncertainty is empirical, not documentary: IndexStoreDB relation population depth for Swift.

### Gaps to Address

- **IndexStoreDB relation depth for Swift (empirical):** The API surface is confirmed, but whether the Swift symbol provider populates `.baseOf`/`.overrideOf`/`.extendedBy` as richly as Clang is unverified. The `SymbolOccurrence.symbolProvider` field (`.swift` vs `.clang`) can be used to filter and compare. **Address in Phase 1 planning** — validate before committing to the full relationship mapping design.
- **Xcode `-destination` resolution for iOS targets:** The current build path uses generic "My Mac" destination; iOS-only targets may not fully index. Scheme parsing approach is undocumented. **Address in a future v0.2.x phase** if iOS coverage becomes a priority.
- **`external_symbols` heuristic accuracy in multi-module packages:** The current referenced-but-undefined heuristic may misclassify cross-module symbols within the same repo. The `isSystem` improvement (Phase 1) addresses system symbols, but internal-module classification needs validation against a real multi-module SwiftPM package.
- **Cache invalidation under partial/interrupted builds:** SwiftPM `--scratch-path` reuse can leave the scratch directory in an inconsistent state after a failed build. The exit-code validation strategy is sound but needs integration testing. **Address in Phase 4 planning.**

## Sources

### Primary (HIGH confidence)
- `.build/checkouts/indexstore-db/Sources/IndexStoreDB/` — IndexStoreDB Swift API source (relations API, lifecycle methods, `SymbolLocation.isSystem`, `SymbolProperty.unitTest`). The exact source the project compiles against.
- `Protos/scip.proto` (vendored from scip-code/scip) — canonical SCIP schema (`Relationship`, `SymbolRole`, `SymbolInformation`, `external_symbols` semantics, `Occurrence`)
- `scip lint` Go source (`cmd/scip/lint.go` from scip-code/scip) — validation rules (`missingRelationshipFlagError`, `missingSymbolInRelationshipError`, `bothLocalAndExternalSymbolError`)
- scip-typescript source (`src/FileIndexer.ts`, `src/ProjectIndexer.ts`) — relationships via ancestor walking, documentation patterns, `--global-caches` is in-process only
- rust-analyzer SCIP CLI (`crates/rust-analyzer/src/cli/scip.rs`) — `relationships: Vec::new()` hardcoded, but populates `documentation`, `signature_documentation`, `enclosing_symbol`
- Homebrew official docs (Formula Cookbook, Taps, Bottles) — formula structure, tap naming, sha256, license, `depends_on macos:`
- `homebrew-core` formulae (`swiftlint.rb`, `swiftformat.rb`, `scip.rb`) — real SwiftPM build-from-source patterns; confirmed no namespace conflict
- Project codebase (`SCIPIndexBuilder.swift`, `SymbolRoleMapping.swift`, `SCIPSymbolFormatter.swift`, `PositionMapping.swift`, `IndexCommand.swift`) — ground truth for current implementation

### Secondary (MEDIUM confidence)
- scip-python README (github.com/sourcegraph/scip-python) — Pyright-based; `--project-name`/`--project-namespace` for cross-repo
- `docs/project-roadmap.md` — current v0.2.0 tentative scope

### Tertiary (needs validation)
- IndexStoreDB relation population depth for Swift — API confirmed from source, but empirical Swift-specific population depth is unverified (gap to address in Phase 1)

---
*Research completed: 2026-08-11*
*Ready for roadmap: yes*
