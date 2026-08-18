# Roadmap: scip-swift

## Milestones

- ✅ **v0.1.0–v0.1.2** — Initial SCIP pipeline (shipped)
- ✅ **v0.2.0** — Symbol enrichment, incremental indexing, cross-repo, Xcode test fixture (shipped 2026-08-13)
- ✅ **v0.3.0 Readable Indexes** — Phases 6–9 (shipped 2026-08-18)

## Phases

<details>
<summary>✅ v0.2.0 (Phases 1–5) — SHIPPED 2026-08-13</summary>

- [x] Phase 1: Symbol Metadata Enrichment (3/3 plans) — relationships, enclosing symbols, role bits, signatures, isSystem classification
- [x] Phase 2: Homebrew Distribution & Release Pipeline (2/2 plans) — formula, universal binary, release CI, dylib guard
- [x] Phase 3: Incremental Indexing (2/2 plans) — persistent DB, content-hash cache, version invalidation, --cache-dir/--index-only
- [x] Phase 4: Cross-Repo Indexing (2/2 plans) — index-many subcommand, version disambiguation, ScipIndexMerger, --merge
- [x] Phase 5: Xcode End-to-End Test Fixture (1/1 plan) — real xcodebuild integration test

Full details: `.planning/milestones/v0.2.0-ROADMAP.md`

</details>

### 🚧 v0.3.0: Readable Indexes (Phases 6–9)

**Milestone Goal:** Make scip-swift's output human-readable and precise — demangled symbol names, exact occurrence ranges, `xcodebuild -destination` support for iOS-only targets, and symbol documentation.

**Cross-phase invariants:** every phase keeps `scip lint` passing and second-run byte-identity tests green (re-baseline where serialized output changes; bump the IndexManifest cache version when it does).

- [x] **Phase 6: Xcode Backend Repair & Destination Selection** - Restore the xcodebuild dispatch branch and add opt-in `--destination`
- [x] **Phase 7: Demangled Symbol Names** - Human-readable Swift symbol names with opaque fallback and stable identity
- [x] **Phase 8: Exact Occurrence Ranges** - SwiftSyntax identifier extents replace display-name-length approximation
- [x] **Phase 9: Symbol Documentation** - Doc comments as Markdown `documentation` riding the same parse pass

## Phase Details

### Phase 6: Xcode Backend Repair & Destination Selection

**Goal**: Xcode-project repos index again, and users can point xcodebuild at an explicit destination so iOS-only targets fully index
**Depends on**: Nothing (first phase of v0.3.0; restores v0.2.x capability lost in the 0cdefd7 cache rewrite)
**Requirements**: REPAIR-01, REPAIR-02, REPAIR-03
**Success Criteria** (what must be TRUE):

  1. User can run `scip-swift index <repo>` on an Xcode-project repo and get a `.scip` index built through the xcodebuild backend (integration test against the existing Xcode fixture passes)
  2. User can pass `--destination "platform=iOS Simulator,name=iPhone 16"` and xcodebuild builds for that destination; omitting the flag preserves today's generic-destination behavior
  3. When a `--destination` build fails, the error output tells the user to run `xcodebuild -showdestinations` to discover valid destination strings

**Plans**: 1/2 plans executed:

- [x] 06-01-PLAN.md — Restore the lost `.xcodebuild` dispatch in `indexOneRepo` via one shared switch-tool helper called from both cache branches (REPAIR-01), with integration tests on the temp and cache paths
- [x] 06-02-PLAN.md — Opt-in `--destination` flag threaded CLI → `indexOneRepo` → `XcodebuildBuildRunner` arguments splice, plus the destination-gated `xcodebuildDestinationFailed` error with `-showdestinations` hint (REPAIR-02, REPAIR-03)

### Phase 7: Demangled Symbol Names

**Goal**: Users see human-readable symbol names in the index while symbol identity, incremental caching, and cross-repo merges behave unchanged
**Depends on**: Nothing (independent track — demangling touches the symbol formatter only; runs after Phase 6 by numbering)
**Requirements**: SYMBOL-01, SYMBOL-02, SYMBOL-03, SYMBOL-04
**Success Criteria** (what must be TRUE):

  1. Swift symbols in the generated `.scip` index display demangled, human-readable names (e.g. `MiniSwift.greet(name:)`) instead of raw `s:`-prefixed USRs
  2. Symbols that cannot be demangled (ObjC/C `c:`-prefixed USRs, future mangling constructs) keep the existing opaque wrapped-USR form, and indexing never fails because of demangling
  3. A second run over unchanged sources produces byte-identical output and cross-repo merges dedupe correctly — the wrapped USR stays the canonical `symbol` field (existing tests re-baselined, cache version bumped)
  4. User can pass `--no-demangle` to reproduce v0.2.x-style opaque output

**Plans**: 2/2 plans executed:

- [x] 07-01-PLAN.md — USRDemangler module (dlopen toolchain libswiftDemangle, s:→_$s rewrite, caller-owned buffer with n+1 truncation retry, fail-soft fallback) wired as a tracer: one real fixture USR demangled into the .scip display_name with identity untouched, plus the unit corpus and the 0.3.0 cache-version bump (SYMBOL-01, SYMBOL-02)
- [x] 07-02-PLAN.md — `--no-demangle` flag threaded CLI → indexOneRepo → builder, external-symbol display names, cache-upgrade invalidation test, and the untouched merge/incremental regression gates (SYMBOL-03, SYMBOL-04)

### Phase 8: Exact Occurrence Ranges

**Goal**: Occurrence ranges are exact — computed from real identifier token extents, correct on Unicode content, with a safe fallback when parsing fails
**Depends on**: Nothing (independent of Phase 7; introduces the swift-syntax dependency and the shared per-file refiner pass that Phase 9 reuses)
**Requirements**: RANGE-01, RANGE-02, RANGE-03
**Success Criteria** (what must be TRUE):

  1. Definitions and references both emit end columns computed from the exact identifier token extent — compound names like `greet(name:)` no longer drift from the display-name-length approximation
  2. Occurrences on lines containing multi-byte content (Unicode/CJK/emoji) earlier on the same line report correct columns, normalized to UTF-8 byte offsets end-to-end (fixture test)
  3. Files SwiftSyntax cannot fully parse (error nodes, macro-expanded code) still index successfully, falling back to name-length end columns for affected occurrences

**Plans**: 2/2 plans:

- [x] 08-01-PLAN.md — swift-syntax 602.0.0 exact pin + SwiftSyntaxRefiner pure module (line-start byte table, token-extent map, nil-on-miss fallback) wired as a tracer: one fixture file's occurrences emit exact ends end-to-end with the getter drift case, plus the Unicode/error-node unit corpus and PositionMapping exact-or-approximate contract (RANGE-01, RANGE-02, RANGE-03)
- [x] 08-02-PLAN.md — UnicodeRangeFixture integration asserting the hand-computed F4 byte-column table and getter-drift elimination end-to-end, broken-source pipeline fallback, and the cache-hit byte-identity path serving exact ranges without re-parse (RANGE-01, RANGE-02, RANGE-03)

### Phase 9: Symbol Documentation

**Goal**: Symbols carry their doc comments as Markdown documentation, extracted on the same parse pass that refines ranges
**Depends on**: Phase 8 (reuses the shared SwiftSyntax per-file parse pass — DOCS-03)
**Requirements**: DOCS-01, DOCS-02, DOCS-03
**Success Criteria** (what must be TRUE):

  1. `///` and `/** */` doc comments appear as Markdown in `SymbolInformation.documentation` for the corresponding symbols (hover parity with scip-typescript/scip-rust)
  2. Non-doc comments (`//`), license headers, and comments on non-declaration tokens do not appear in any documentation field
  3. A file gets exactly one SwiftSyntax parse per indexing run — documentation extraction shares the Phase 8 refiner pass, not a second parse

**Plans**: 1/1 plans executed

- [x] 09-01-PLAN.md — Name-token-keyed doc map inside the Phase 8 SwiftSyntaxRefiner parse (D1), builder wiring of `documentation` on definition hits with getter/setter inheritance (D3), full normalization/exclusion corpus (D4), per-file parse-count proof (D5), DocumentationFixture end-to-end with cache round-trip and zero-re-baseline protected-file gates (DOCS-01, DOCS-02, DOCS-03)

## Progress

**Execution Order:**
Phases execute in numeric order: 6 → 7 → 8 → 9 (Phases 7 and 8 are independent tracks; 9 requires 8)

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 6. Xcode Backend Repair & Destination Selection | v0.3.0 | 1/2 | In Progress|  |
| 7. Demangled Symbol Names | v0.3.0 | 2/2 | In Progress|  |
| 8. Exact Occurrence Ranges | v0.3.0 | 0/2 | Not started | - |
| 9. Symbol Documentation | v0.3.0 | 1/1 | In Progress|  |
