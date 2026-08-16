---
phase: 07-demangled-symbol-names
plan: 02
subsystem: scip-swift
tags: [no-demangle-flag, external-symbols, cache-upgrade, v0.2.x-parity]
requires:
  - SCIPIndexBuilder demangle seam (07-01)
  - USRDemangler dlopen + memoization (07-01)
  - ScipSwiftVersion 0.3.0 (07-01)
provides:
  - "--no-demangle CLI flag threaded to SCIPIndexBuilder(demangle:)"
  - External-symbol display names (demangled when on, empty when off)
  - Cache-upgrade proof: 0.2.1 cache dirs regenerate demangled documents
  - invalidateAll scoped to docs/ + manifest.json (build scratch survives)
affects:
  - CacheStoreTests invalidateAll contract (corrected to scoped semantics)
key-files:
  created: []
  modified:
    - Sources/scip-swift/Commands/IndexCommand.swift
    - Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift
    - Sources/scip-swift/Caching/CacheStore.swift
    - Tests/scip-swiftTests/IntegrationTests.swift
    - Tests/scip-swiftTests/IndexManifestTests.swift
    - Tests/scip-swiftTests/IncrementalIntegrationTests.swift
    - Tests/scip-swiftTests/CacheStoreTests.swift
decisions:
  - External USR recovered by inverting the canonical symbol string's trailing
    descriptor, not via a makeDocument-accumulated map — the map is empty on
    cache-hit runs and would break secondRunIdentical byte-identity
  - invalidateAll removes docs/ + manifest.json only; indexOneRepo parks its
    build scratch (build-scratch/, index-db/) inside the cache dir and that
    must survive version-upgrade invalidation
  - --help surface check shells out to the freshly built .build/debug/scip-swift
metrics:
  duration: 58m
  completed: 2026-08-16
status: complete
actuals:
  tokens: 4060  # chars/4 over realized diff (16239 chars, 7 files)
  tasks: 3
  commits: 6
---

# Phase 7 Plan 2: Demangled Symbol Names (expansion) Summary

`--no-demangle` flag threaded CLI → indexOneRepo → builder reproducing v0.2.x opaque display names exactly, external symbols gaining demangled display names via the shared memoized demangler, and a cache-upgrade test that exposed and fixed a real invalidation bug (invalidateAll was deleting the freshly-built index store).

## What Was Built

### Task 1 — `--no-demangle` flag threading (SYMBOL-04) — RED `1dee3b9` / GREEN `4acc0e4`

RED added three tests to `IntegrationTests`:
- `demangle off reproduces v0.2.x opaque display names` — builder constructed with the existing `demangle: false` seam over the real fixture asserts exact-match short names (`Greeter`, `greet()`, `name`) and asserts no demangled name leaks through.
- `external symbols stay empty when demangle is off` — v0.2.x externals parity (research D7).
- `index --help advertises --no-demangle` — shells out to `.build/debug/scip-swift index --help` for a real CLI-surface check. This row was the failing RED evidence (1 issue); the two builder-level rows passed trivially against the 07-01 seam, exactly as the plan predicted.

GREEN added `@Flag(name: .long, help: "Emit v0.2.x opaque symbol display names instead of demangled ones.") var noDemangle = false` to `IndexCommand` beside `indexOnly`, threaded as a defaulted `demangle: Bool = true` parameter on `indexOneRepo` (after `symbolVersion`, the Phase-6 `destination` pattern), passed `demangle: !noDemangle` from `run()`, and forwarded into `SCIPIndexBuilder(demangle:)`. `IndexManyCommand` untouched — compiles unchanged via the default (research D5).

### Task 2 — external-symbol display names (research D7) — RED `ea9e4a9` / GREEN `8e5da08`

RED `external symbols carry demangled display names when demangle is on` failed with 3 issues: no `Swift.String`-containing external name, and two externals with empty display names whose USRs demangle (the failures printed the exact expected values `Swift.String` and `Swift.String.init(stringInterpolation:)`, confirming the research corpus).

GREEN fills `info.displayName` in `build()`'s externalSymbols loop from the same per-run memoized `USRDemangler` instance (D6 — no second instance), leaving it empty when the demangler is nil (off mode). One compile fix mid-task (Substring reassignment type error), within the attempt limit.

**USR-recovery choice (per the plan's note-the-choice instruction):** the plan offered a per-run `[String: String]` canonical-string→USR map accumulated in `makeDocument`, or passing the name through `referencedSymbols`. The map is unworkable: on cache-hit runs documents are served from cache, `makeDocument` never runs, the map is empty, externals lose their names, and `secondRunIdentical` breaks (`data1 != data2`). Instead the builder inverts the canonical symbol string's trailing descriptor — the USR rides verbatim inside `` `<usr>`. `` per `SCIPSymbolFormatter.escapeIdentifierName`, so `usr(fromCanonicalSymbolString:)` unescapes it. This is cache-independent (occurrences carry canonical strings whether fresh or cached) and keeps the change confined to the builder. Byte-identity proven by `secondRunIdentical` passing unmodified.

### Task 3 — cache-upgrade invalidation + identity gate (SYMBOL-03) — RED `5e66f00` / fix `9c38bfd`

RED added:
- Unit row in `IndexManifestTests`: a manifest written with `converterVersion: "0.2.1"` reports `isCompatibleWith(converterVersion: ScipSwiftVersion.version) == false` (passed immediately — mechanism predates the phase, kept as the regression row the plan called for).
- Integration `0.2.1 cache dir regenerates after upgrade` in `IncrementalIntegrationTests`: seeds a `CacheStore` with a 0.2.1 manifest plus a stale serialized `Scip_Document` for `Greeter.swift` (hash derived via `ContentHasher` exactly as the builder does, file named only as `<hash>.scipdoc`) whose symbol carries the v0.2.x short name `Greeter`, then runs `indexOneRepo` with the real version constant. **Failed** with `index.documents.first { ... } → nil` — a genuine empty index, not a stale serve.

That failure exposed a real bug (Rule 1, auto-fixed): `CacheStore.invalidateAll()` deleted the entire cache directory, but `indexOneRepo` builds the index store into `cacheDir/build-scratch` and opens `cacheDir/index-db` before the manifest check runs — so every version-upgrade run with a persistent cache nuked its own inputs and silently produced an empty index. Fix (`9c38bfd`): `invalidateAll` removes only the store's own artifacts (`docs/` and `manifest.json`); the cache dir and the caller's build scratch survive. `CacheStoreTests.invalidateAllRemovesDir` asserted the old whole-dir-removal contract and was rewritten as `invalidateAll removes cached docs and manifest, keeps the cache directory` — that suite is not one of the plan's protected guards. After the fix: the upgrade test proves regeneration (demangled `MiniSwiftPackage.Greeter` present, short `Greeter` absent, manifest refreshed to 0.3.0), and all three pre-existing incremental tests pass **unmodified**.

## Verification Evidence

- `swift test --filter IntegrationTests` (matches 4 suites) — 14/14 passed, Tasks 1 and 2 GREEN gates
- `swift test --filter IndexManifestTests` — 8/8
- `swift test --filter IncrementalIntegrationTests` — 4/4 (3 pre-existing rows unmodified + new upgrade row)
- `swift test --filter ScipIndexMerger` — 10/10, zero edits
- `swift test --filter CacheStoreTests` — 7/7 with the corrected invalidateAll contract
- Phase gate `swift test --skip Xcode` — **106 tests / 15 suites, all passed**
- Partition-union completion `swift test --filter Xcode` — **19 tests / 3 suites, all passed**
- Total: **125 tests, 0 failures** across the partition union (was 119 at wave-1 end; +6 new rows, +1 rewritten contract row)
- Protected-file gate: `git diff --stat 815c282 -- Tests/scip-swiftTests/ScipIndexMergerTests.swift Tests/scip-swiftTests/MultiRepoMergeIntegrationTests.swift` — empty (byte-identical to phase base)
- `IndexManyCommand.swift` — no edits this plan; compiles via the defaulted parameter

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] invalidateAll destroyed the freshly-built index store on version upgrade**

- **Found during:** Task 3 RED (cache-upgrade integration test failed with an empty index)
- **Issue:** `CacheStore.invalidateAll()` removed the whole cache dir, including `build-scratch/` (the index store `indexOneRepo` had just built) and `index-db/`. Any real user upgrading 0.2.1 → 0.3.0 with a persistent cache got a silent empty index instead of regenerated documents. The stale cache never served stale names, but regeneration never happened either.
- **Fix:** Scoped `invalidateAll` to `docs/` + `manifest.json` with a WHY comment on the ownership boundary. Build scratch is owned by the build step, not the document cache.
- **Files modified:** Sources/scip-swift/Caching/CacheStore.swift, Tests/scip-swiftTests/CacheStoreTests.swift
- **Commit:** 9c38bfd

**2. [Plan-choice note] External USR recovery inverts the canonical symbol string instead of a makeDocument-accumulated map**

- **Found during:** Task 2 design, before writing the GREEN change
- **Issue:** The plan's first option (canonical→USR map accumulated in `makeDocument`) is unsound on cache-hit runs: documents served from cache never pass through `makeDocument`, the map stays empty, external display names vanish on the second run, and `secondRunIdentical` fails.
- **Fix:** `usr(fromCanonicalSymbolString:)` unescapes the USR from the trailing `` `<usr>`. `` descriptor the formatter already emits — deterministic and cache-independent. Smallest change consistent with D6's single-memoized-instance rule; the plan explicitly allowed choosing and noting.
- **Files modified:** Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift
- **Commit:** 8e5da08

## Deferred Issues

None. The `.gitignore` `build/`-pattern note from 07-01 remains (out of scope here; tracked in 07-01-SUMMARY).

## TDD Gate Compliance

- Task 1: RED `test(07-02)` `1dee3b9` (help-row failure observed) → GREEN `feat(07-02)` `4acc0e4`
- Task 2: RED `test(07-02)` `ea9e4a9` (3 issues observed) → GREEN `feat(07-02)` `8e5da08`
- Task 3: RED `test(07-02)` `5e66f00` (empty-index failure observed) → fix `fix(07-02)` `9c38bfd`
- No test was weakened; the one rewritten test (`CacheStoreTests.invalidateAll`) had its contract corrected to match the bug fix, not the feature.

## Self-Check: PASSED

- Sources/scip-swift/Commands/IndexCommand.swift — FOUND, modified (commits 4acc0e4)
- Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift — FOUND, modified (commit 8e5da08)
- Sources/scip-swift/Caching/CacheStore.swift — FOUND, modified (commit 9c38bfd)
- Tests/scip-swiftTests/IntegrationTests.swift — FOUND, modified (commits 1dee3b9, ea9e4a9)
- Tests/scip-swiftTests/IndexManifestTests.swift — FOUND, modified (commit 5e66f00)
- Tests/scip-swiftTests/IncrementalIntegrationTests.swift — FOUND, modified, additions only (commit 5e66f00)
- Commits 1dee3b9, 4acc0e4, ea9e4a9, 8e5da08, 5e66f00, 9c38bfd — FOUND in git log
