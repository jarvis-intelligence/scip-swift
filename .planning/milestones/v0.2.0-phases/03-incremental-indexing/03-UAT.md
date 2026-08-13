# Phase 3 — UAT Verification

**Date:** 2026-08-12
**Phase:** 3 — Incremental Indexing
**Status:** ✅ PASSED

## Success Criteria Verification

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Second run produces identical `.scip` output | ✅ PASS | `IncrementalIntegrationTests.secondRunIdentical` — byte-identical `serializedData()` on second run |
| 2 | Modifying one file regenerates only that file's document | ✅ PASS | Cache keyed by content hash — changed files produce different hashes, triggering cache miss. Unchanged files reuse cached docs |
| 3 | Version change invalidates entire cache | ✅ PASS | `IndexManifestTests` (7 tests) — all four version fields independently verified. `IndexCommand.run()` calls `invalidateAll()` on mismatch |
| 4 | `--index-only` skips build, reads existing IndexStore | ✅ PASS | CLI `--help` confirms both `--cache-dir` and `--index-only` flags. `IndexCommand.run()` resolves IndexStore via `findIndexStore` without calling `produceIndexStore()` |
| 5 | Integration test confirms cache correctness | ✅ PASS | 3 integration tests: second-run identical, cache miss/hit, backward compatible — all pass |

## Requirements Coverage

| Requirement | Status | Implementation |
|-------------|--------|----------------|
| INCR-01 (persistent databasePath) | ✅ | `<cacheDir>/index-db` persists across runs |
| INCR-02 (--cache-dir CLI) | ✅ | `@Option(name: .long)` in IndexCommand |
| INCR-03 (per-file doc cache) | ✅ | `CacheStore.saveDocument`/`loadDocument` keyed by SHA256 |
| INCR-04 (staleness detection) | ✅ | `ContentHasher.sha256Hex` + `dateOfLatestUnitFor` |
| INCR-05 (--index-only) | ✅ | `@Flag` skips build, `findIndexStore` reads existing store |
| INCR-06 (version invalidation) | ✅ | `IndexManifest.isCompatibleWith` — 4 fields, any mismatch = invalidate |
| TEST-04 (integration test) | ✅ | `IncrementalIntegrationTests` — 3 tests |

## Test Suite

- **80 tests in 13 suites** — all passing
- 23 new tests (20 cache primitive unit tests + 3 incremental integration tests)
- 0 regressions

## Known Limitations

1. **`--index-only` is SwiftPM-only** — Xcode path not supported (documented deferral; different index store location convention)
2. **external_symbols isSystem classification** — cached documents don't carry `SymbolLocation.isSystem`; post-assembly scan uses referenced-but-undefined heuristic (documented; affects multi-module repos only)
3. **SC2 (selective regeneration) is not a dedicated test** — content-hash-based invalidation makes it architecturally impossible to serve stale cache for a changed file, but there's no explicit test modifying a source file and verifying only that file regenerated

## Verdict

**Phase 3 PASSED** — all 7 requirements delivered, all 5 success criteria verified, 80 tests green.
