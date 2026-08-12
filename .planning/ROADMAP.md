# Roadmap: scip-swift v0.2.0

## Overview

scip-swift v0.2.0 closes the parity gaps between scip-swift and peer indexers (scip-typescript, scip-rust, scip-python) across four fronts: symbol metadata enrichment (the highest-impact gap — relationships are fetched from the compiler and silently discarded), Homebrew distribution, incremental indexing, and cross-repo linking. The journey flows from enrichment-first (cache schema must be stable before caching exists) through infrastructure and performance, culminating in multi-repo support and the Xcode test fixture that closes the last coverage gap. All 26 v0.2.0 requirements map across five phases with zero orphans.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Symbol Metadata Enrichment** - Map relationships, enclosing symbols, expanded roles, signatures, and isSystem classification (highest-impact gap)
- [ ] **Phase 2: Homebrew Distribution & Release Pipeline** - Custom tap, universal binary, release CI, dylib runtime guard
- [ ] **Phase 3: Incremental Indexing** - Persistent cache, content-hash invalidation, --cache-dir and --index-only modes
- [ ] **Phase 4: Cross-Repo Indexing** - index-many subcommand, symbol version field, merge mode, cross-repo reference resolution
- [ ] **Phase 5: Xcode End-to-End Test Fixture** - Minimal .xcodeproj fixture closing the Xcode test-coverage gap

## Phase Details

### Phase 1: Symbol Metadata Enrichment
**Goal**: The emitted `.scip` index contains relationships (inheritance, conformance, override), enclosing symbols for locals, expanded role bits (Test, Generated, ForwardDefinition), basic signatures, and authoritative external-symbol classification — enabling "Find implementations" and protocol/override navigation that peer indexers already provide
**Depends on**: Nothing (first enrichment phase; must be stable before Phase 3 caching)
**Requirements**: META-01, META-02, META-03, META-04, META-05, META-06, TEST-02, TEST-03
**Success Criteria** (what must be TRUE):
  1. Indexing a file with `class B: A {}` produces a `Relationship` on `B` pointing to `A` with `is_implementation = true`, and "Find implementations" on `A` returns `B` in a SCIP consumer
  2. Local symbols (function-local variables/parameters) have `enclosing_symbol` populated, so they appear nested under their containing scope in symbol outlines
  3. Swift Testing / XCTest symbols carry the `Test` role bit, and `override func` symbols carry `ForwardDefinition`
  4. `external_symbols` contains only system/stdlib symbols (verified via `SymbolLocation.isSystem`), not project-internal cross-module symbols
  5. `signature_documentation` is populated on function/variable/type symbols with reconstructed signatures (e.g., `func greet(name:)`), improving hover tooltips from bare to useful
**Plans**: 3 plans
Plans:
- [ ] 01-01-PLAN.md — Tracer: spike fixture validating relation population (META-06), RelationshipMapping mapper + SCIPIndexBuilder wiring (META-01, TEST-02)
- [ ] 01-02-PLAN.md — Expand SymbolRoleMapping with ForwardDefinition/Test bits (META-03, TEST-03), populate enclosing_symbol from .childOf (META-02)
- [ ] 01-03-PLAN.md — Replace external_symbols heuristic with isSystem (META-04), create SignatureMapping mapper (META-05)

### Phase 2: Homebrew Distribution & Release Pipeline
**Goal**: Users can install scip-swift via `brew install` from a custom tap, with an automated release pipeline producing universal binaries and a formula updated on every tagged release — fully independent of the mapping work
**Depends on**: Nothing (pure infrastructure; can run in parallel with Phase 1)
**Requirements**: DIST-01, DIST-02, DIST-03, DIST-04
**Success Criteria** (what must be TRUE):
  1. A user can run `brew install phuongddx/scip-swift/scip-swift` and get a working binary without building from source
  2. Push of a `v*` tag triggers a GitHub Actions workflow that builds a universal (arm64 + x86_64) binary, uploads it to GitHub Releases, and updates the Homebrew formula SHA256
  3. Running the binary on a machine with only CommandLineTools (no Xcode) produces a clear, actionable error message directing the user to install Xcode — not a cryptic dylib crash
  4. The universal binary runs natively on both Apple Silicon and Intel Macs
**Plans**: 2 plans
Plans:
- [ ] 02-01-PLAN.md — Runtime dylib existence guard with actionable error (DIST-04)
- [ ] 02-02-PLAN.md — Homebrew formula template + release CI pipeline with universal binary build (DIST-01, DIST-02, DIST-03)

### Phase 3: Incremental Indexing
**Goal**: Re-indexing a repo reuses cached per-file `Scip_Document` protobufs for unchanged files, significantly reducing rebuild time for repos >100 files — with a correctness guarantee that stale cache is never served
**Depends on**: Phase 1 (enrichment must be stable so cached documents already contain relationships/signatures — otherwise the first post-cache enrichment invalidates every entry)
**Requirements**: INCR-01, INCR-02, INCR-03, INCR-04, INCR-05, INCR-06, TEST-04
**Success Criteria** (what must be TRUE):
  1. A second `scip-swift` run on an unchanged repo produces an identical `.scip` output while skipping the build step for unchanged files (measurable speedup)
  2. Modifying one source file causes only that file's `Scip_Document` to be regenerated; all other cached documents are reused
  3. Changing the Swift toolchain version, indexstore-db version, or scip-swift version invalidates the entire cache (no stale data served)
  4. `--index-only` mode skips the build step entirely and reads an existing IndexStore directly, enabling CI to reuse a prior build
  5. Integration test confirms cache correctness: index → modify source → re-index → changed symbols updated, unchanged symbols preserved, `scip lint` still passes
**Plans**: 2 plans
Plans:
- [ ] 03-01-PLAN.md — Cache layer primitives: ContentHasher (SHA256), IndexManifest (version invalidation), CacheStore (protobuf document I/O) — TDD
- [ ] 03-02-PLAN.md — Tracer: wire cache into SCIPIndexBuilder.build() + CLI flags --cache-dir/--index-only + integration test (TEST-04)

### Phase 4: Cross-Repo Indexing
**Goal**: scip-swift can index multiple repositories and optionally merge them into a single `.scip` output, with symbol version disambiguation preventing collisions across same-named modules
**Depends on**: Phase 1 (relationships provide cross-repo linking value) + Phase 3 (incremental benefits multi-repo builds)
**Requirements**: CROSS-01, CROSS-02, CROSS-03, CROSS-04, CROSS-05, TEST-05
**Success Criteria** (what must be TRUE):
  1. `scip-swift index-many <repoA> <repoB>` indexes each repo independently, producing separate `.scip` files
  2. The `version` field in SCIP symbol strings is populated, disambiguating same-named modules across different repos
  3. `--merge` flag combines multiple `.scip` indexes into a single output that passes `scip lint` with no duplicate-symbol warnings
  4. Cross-repo references resolve via the SCIP `external_symbols` mechanism — a symbol referenced in RepoA but defined in RepoB resolves correctly in the merged index
  5. Integration test confirms: index two repos with same-named modules → merge → `scip lint` passes → cross-repo "go to definition" works
**Plans**: TBD

### Phase 5: Xcode End-to-End Test Fixture
**Goal**: The Xcode build path is validated by a real end-to-end integration test (not argument assertions only), preventing silent regressions for Xcode-only projects
**Depends on**: Nothing (test infrastructure; can be developed any time)
**Requirements**: TEST-01
**Success Criteria** (what must be TRUE):
  1. A minimal `.xcodeproj` fixture exists under `Fixtures/` and is committed to the repo
  2. CI runs an integration test that builds the Xcode fixture with indexing enabled and indexes it end-to-end via `scip-swift`
  3. The test fails if `XcodebuildBuildRunner` regresses (e.g., broken IndexStore discovery, scheme resolution failure) — catching Xcode-only breakage before it ships
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

**Parallelism note:** Phases 1 and 2 are independent and may be developed concurrently if capacity allows. Phase 5 is also independent and can be slotted in any time. Phases 3 and 4 have hard dependencies (3 on 1; 4 on 1+3) and must respect the execution order.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Symbol Metadata Enrichment | 0/3 | Planned | - |
| 2. Homebrew Distribution & Release Pipeline | 0/2 | Planned | - |
| 3. Incremental Indexing | 0/2 | Planned | - |
| 4. Cross-Repo Indexing | 0/TBD | Not started | - |
| 5. Xcode End-to-End Test Fixture | 0/TBD | Not started | - |

---

## Phase Risk Register

Risks sourced from research `PITFALLS.md`. Each phase carries the pitfalls its work must prevent.

### Phase 1 Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Pitfall 1 — Relationships silently dropped**: `occurrence.relations` is fetched and discarded; "Find implementations" returns nothing | HIGH | Read `occurrence.relations` in `makeDocument()`; map `.baseOf`/`.extendedBy` → `is_implementation`, `.overrideOf` → `is_reference`, `.childOf` → `enclosing_symbol` |
| **Pitfall 2 — Relationship booleans set incorrectly**: wrong `is_reference`/`is_implementation` flags break Find References or Find Implementations | HIGH | Define explicit mapping table validated against `scip.proto` TypeScript example BEFORE writing mapping code; every `Relationship.symbol` must exist in the index or `scip lint` errors |
| **Pitfall 6 — `external_symbols` misclassified**: heuristic emits project-internal symbols as external; breaks multi-repo merge | MEDIUM | Replace heuristic with `SymbolLocation.isSystem` classification (META-04) |

**Phase 1 spike (META-06):** Empirically validate that the Swift compiler populates `occurrence.relations` with the same depth as Clang BEFORE committing to the full relationship mapping design. This is the single biggest unknown in the roadmap. If Swift relation depth is shallow, the relationship mapping scope must be reduced accordingly.

### Phase 2 Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Pitfall 5 — Homebrew binary crashes (dylib not found)**: `libIndexStore.dylib` ships only with Xcode, not CommandLineTools; cannot be a Homebrew dependency | HIGH | Add runtime dylib-resolution check with clear, actionable error message (DIST-04); document Xcode requirement prominently in formula `desc` and README |

### Phase 3 Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Pitfall 3 — Stale incremental cache serves bad data**: IndexStoreDB reused without polling for changes; partial build produces incomplete store | HIGH | Always open fresh with `waitUntilDoneInitializing: true`; use `dateOfLatestUnitFor(filePath:)` for staleness; validate build exit code 0; include `.swift-version` + scip-swift version in cache key (INCR-06) |
| **USR instability across toolchains**: cache keys based on USR silently invalidated on Swift upgrade | MEDIUM | Include `.swift-version` hash in cache key; document that upgrading Swift invalidates cache |

**Cache schema stability (hard dependency):** Phase 1 enrichment MUST land before Phase 3. Cached `Scip_Document` protobufs must already contain relationships/signatures when written — otherwise the first enrichment improvement after caching ships invalidates every cache entry, yielding zero benefit.

### Phase 4 Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Pitfall 4 — Multi-repo symbol collision**: same module name in different repos produces identical SCIP symbol strings; different toolchain versions produce different USRs | HIGH | Require same toolchain across repos (validate `.swift-version` match before merge); populate `version` field in symbol format (CROSS-03); run `scip lint` on merged index |
| **Pitfall 6 (cross-repo aspect) — merged index fails lint**: external_symbols from RepoA duplicate defined symbols in RepoB | MEDIUM | Suppress external_symbols emission in multi-repo merge mode; let consumer resolve cross-repo refs from loaded indexes |

**Symbol version field (hard dependency):** CROSS-03 (populate `version` field in SCIP symbol strings) must be implemented before multi-repo merge (CROSS-04) can work without collisions. This field is currently hardcoded empty in `SCIPSymbolFormatter`.

### Phase 5 Risks

No pitfalls from research apply — this is pure test infrastructure. The risk it *mitigates* is silent regression in `XcodebuildBuildRunner` breaking Xcode-only projects, which has no other coverage.

---

## Coverage

| Requirement | Phase | Status |
|-------------|-------|--------|
| META-01 | Phase 1 | Pending |
| META-02 | Phase 1 | Pending |
| META-03 | Phase 1 | Pending |
| META-04 | Phase 1 | Pending |
| META-05 | Phase 1 | Pending |
| META-06 | Phase 1 | Pending |
| TEST-02 | Phase 1 | Pending |
| TEST-03 | Phase 1 | Pending |
| DIST-01 | Phase 2 | Pending |
| DIST-02 | Phase 2 | Pending |
| DIST-03 | Phase 2 | Pending |
| DIST-04 | Phase 2 | Pending |
| INCR-01 | Phase 3 | Pending |
| INCR-02 | Phase 3 | Pending |
| INCR-03 | Phase 3 | Pending |
| INCR-04 | Phase 3 | Pending |
| INCR-05 | Phase 3 | Pending |
| INCR-06 | Phase 3 | Pending |
| TEST-04 | Phase 3 | Pending |
| CROSS-01 | Phase 4 | Pending |
| CROSS-02 | Phase 4 | Pending |
| CROSS-03 | Phase 4 | Pending |
| CROSS-04 | Phase 4 | Pending |
| CROSS-05 | Phase 4 | Pending |
| TEST-05 | Phase 4 | Pending |
| TEST-01 | Phase 5 | Pending |

**Coverage: 26/26 v0.2.0 requirements mapped. 0 orphans. 0 duplicates.** ✓

---

*Roadmap created: 2026-08-11*
*Granularity: standard*
*Milestone: v0.2.0 (brownfield — all phases modify shipped v0.1.2 codebase)*
