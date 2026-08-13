# Milestones

## v0.2.0 Symbol Enrichment, Incremental, Cross-Repo, Xcode (Shipped: 2026-08-13)

**Phases completed:** 5 phases, 10 plans, 7 tasks

**Key accomplishments:**

- Symbol metadata enrichment: relationships (inheritance, conformance, override), enclosing symbols, expanded role bits (Test, Generated, ForwardDefinition), basic signatures, and authoritative external-symbol classification via `SymbolLocation.isSystem`
- Homebrew distribution: formula in `homebrew-scip-swift` tap, universal binary (arm64 + x86_64) build, release CI workflow on `v*` tags, runtime dylib resolution guard
- Incremental indexing: persistent IndexStoreDB database, content-hash caching of per-file `Scip_Document` protobufs, version-based invalidation, `--cache-dir` and `--index-only` CLI flags
- Cross-repo indexing: `index-many` subcommand with variadic repo paths, SCIP version field disambiguation, `ScipIndexMerger` with document path prefixing and external-symbol stripping/dedup, `--merge` flag
- Xcode end-to-end test fixture: minimal `.xcodeproj` with real `xcodebuild` → IndexStore → SCIPIndexBuilder integration test, closing the last test-coverage gap

**Stats:** 5 phases, 10 plans, 95 tests across 16 suites, ~6000 LOC Swift, 48 commits, 19 days (2026-07-25 → 2026-08-13)

---
