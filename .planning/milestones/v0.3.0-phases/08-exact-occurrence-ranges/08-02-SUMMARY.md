---
phase: 08-exact-occurrence-ranges
plan: 02
subsystem: integration-tests
tags: [integration, unicode-ranges, utf8, error-recovery, cache, fixtures]
requires:
  - "SwiftSyntaxRefiner exact token-extent map (08-01)"
  - "PositionMapping singleLineRange(exactEndColumn:) (08-01)"
  - "swift-syntax 602.0.0 exact pin (08-01)"
provides:
  - "Fixtures/UnicodeRangeFixture — F4 byte-exact Unicode source through the real SwiftPM pipeline"
  - "Fixtures/BrokenSourceFixture — stale-index corruption scenario for RANGE-03 end-to-end"
  - "Integration proof that the complete F4 hand-computed table emits from a real .scip"
  - "Cache-hit path proven to serve exact (not approximate) getter ranges byte-identically"
affects:
  - "Tests/scip-swiftTests/IntegrationTests.swift (F4 suite + broken-source suite)"
  - "Tests/scip-swiftTests/IncrementalIntegrationTests.swift (cache-hit exact-range assertion)"
tech-stack:
  added: []
  patterns:
    - "stale-index corruption testing: build valid, corrupt on disk, index against the built store"
key-files:
  created:
    - Fixtures/UnicodeRangeFixture/Package.swift
    - Fixtures/UnicodeRangeFixture/Sources/UnicodeRange/main.swift
    - Fixtures/BrokenSourceFixture/Package.swift
    - Fixtures/BrokenSourceFixture/Sources/BrokenSource/Recoverable.swift
  modified:
    - Tests/scip-swiftTests/IntegrationTests.swift
    - Tests/scip-swiftTests/IncrementalIntegrationTests.swift
decisions:
  - "RANGE-03 end-to-end is a stale-index scenario, not a committed broken file — swift build fails hard on any syntax error (even inside inactive #if branches, empirically verified), so a committed broken file can never produce occurrences to refine"
  - "Getter occurrences are located by mangled USR fragment (Swift mangles non-ASCII identifiers: 名前 → 006ldrIFb), following the wave-1 USR-lookup pattern"
  - "F4 discardable uses (_ = emoji / _ = 名前) live after line 4 so the five hand-computed lines stay byte-exact on lines 0-4"
metrics:
  duration: "55m"
  completed: "2026-08-17"
status: complete
actuals:
  tokens: 3716
  tasks: 3
  commits: 3
---

# Phase 8 Plan 02: Integration Proofs Summary

One-liner: Unicode fixture package driven through the real SwiftPM build pipeline emits the byte-verified F4 range table exactly (with getter drift proven eliminated), broken source indexes with graceful approximation fallback, and cache hits serve exact ranges byte-identically without re-parsing.

## What Was Built

- **Fixtures/UnicodeRangeFixture** — swift-tools 6.2 executable package; `main.swift` carries the F4 source byte-exact on lines 0-4 (hexdump-verified: `let emoji = "🦖"` / `let 名前 = greet(name: "日本語")` / blank / `func greet(name: String) -> String {` / `  "Hello, \(name) 🎉"`), with `_ = emoji` / `_ = 名前` discardable uses after line 4 so the compiler emits reference occurrences without shifting the hand-computed columns.
- **F4 integration suite** (`IntegrationTests.unicodeFixtureEmitsHandComputedF4RangeTable`) — full pipeline (SwiftPMBuildRunner → IndexStoreDB → SCIPIndexBuilder) over the fixture, asserting every F4 row via USR-fragment symbol lookup: emoji def/getter L0 [4,9); 名前 def/getter L1 [4,10); greet ref L1 [13,18); greet def L3 [5,10); name param def L3 [11,15); String refs L3 [17,23) and [28,34); init(stringInterpolation:) L4 [2,3); interpolation name ref L4 [12,16). The two getter rows are symbol-linked by accessor USR (`vg` suffix) and carry explicit anti-approximation checks: getter:emoji end == 9 (not 16), getter:名前 end == 10 (not 17).
- **Broken-source pipeline suite** (`IntegrationTests.brokenSourceStillIndexesWithExactEnds`) — builds valid `Recoverable.swift`, corrupts it on disk, then indexes: the document survives with occurrences; `getter:value` keeps the exact token end [4,9) because line 0 is byte-identical between the indexed and corrupted content; `getter:tailValue` carries the name-length approximate end 20 where its stale anchor misses the corrupted token map. Both directions of the fallback contract (exact on hit, approximate on miss) are asserted end-to-end.
- **Cache-hit exact-range suite** (`IncrementalIntegrationTests.cacheHitServesExactRanges`) — Unicode fixture built twice through one shared CacheStore: `data1 == data2` byte-identity plus the cached run's getter:名前 occurrence carries exact end 10 (never approximate 17), proving cache hits (which skip `makeDocument`, research D2) serve refiner-exact ranges.
- No `SCIPIndexBuilder.swift` edit was required — wave-1 wiring already routes cached documents and fresh parses correctly; the plan anticipated this ("expect no edit").

## How to Verify

```sh
swift test --filter IntegrationTests              # F4 table + getter drift proofs + broken-source pipeline
swift test --filter IncrementalIntegrationTests   # byte-identity + cache-serves-exact assertion
swift test --skip Xcode                           # 120 tests / 17 suites — full non-xcodebuild partition
swift test --filter XcodeIntegrationTests         # 5 tests — completes the partition union (125 total)
```

## Commits

| Task | Commit | Type | Summary |
|------|--------|------|---------|
| 1 (RED) | `374837a` | test | failing Unicode fixture F4 range-table integration test |
| 1 (GREEN) | `a67a535` | feat | Unicode fixture emits the hand-computed F4 range table end-to-end |
| 2 | `a9dff2b` | feat | broken-source pipeline fallback + cache-hit exact-range assertions |

## TDD Gate Compliance

RED (`374837a`) failed on the expected missing fixture (`The file "UnicodeRangeFixture" doesn't exist`) before any fixture existed; GREEN (`a67a535`) passed with the fixture as the only implementation change. Task 2 followed RED-first: broken-source test failed on missing `Broken.swift`, cache test passed immediately on wave-1 wiring (the plan's anticipated no-source-change path).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] 名前 USR mangling corrected in symbol-fragment filters**
- **Found during:** Task 1 GREEN
- **Issue:** The plan's suggested display-name heuristics can't locate `名前` occurrences — Swift mangles non-ASCII identifiers inside USRs (`名前` → `006ldrIFb`), so literal-name filters matched nothing.
- **Fix:** Filter by verified mangled USR fragments (`006ldrIFbSSvg`/`006ldrIFbSSvp`), mirroring wave-1's USR-lookup pattern. All other F4 rows matched their literal fragments on first run.
- **Files modified:** Tests/scip-swiftTests/IntegrationTests.swift
- **Commit:** `a67a535`

**2. [Rule 1 - Bug] RANGE-03 fixture reshaped to a stale-index scenario**
- **Found during:** Task 2 GREEN
- **Issue:** The plan's premise that "SwiftPM compiles error files into the index store" is empirically false on Swift 6.2.4 — `swift build` fails hard on any syntax error (verified with `swiftc -typecheck`: even `struct Broken { let x: = }` inside an inactive `#if false` branch is diagnosed and exits 1), and `SwiftPMBuildRunner` throws on non-zero exit, so no occurrences would ever exist to refine.
- **Fix:** Dedicated `Fixtures/BrokenSourceFixture`: build the valid file, corrupt it on disk after the build, then run `SCIPIndexBuilder` against the already-produced index store. The pipeline must still emit the document with exact ends on the byte-identical valid region and approximate ends where stale anchors miss — the fallback contract RANGE-03 actually guarantees. The fixture self-restores via defer.
- **Files modified:** Tests/scip-swiftTests/IntegrationTests.swift, Fixtures/BrokenSourceFixture/* (new)
- **Commit:** `a9dff2b`

No other deviations. PHASE_BASE/WAVE2_BASE scratch markers were removed after final gates passed, per orchestration instruction (the phase has no wave 3).

## Requirements Delivered

- **RANGE-01** — exact identifier ends end-to-end on defs and refs: the complete F4 table from a real `.scip`; getter:emoji 9-not-16 and getter:名前 10-not-17 drift proofs asserted symbol-linked; MiniSwiftPackage tracer (from 08-01) still green in the same suite run.
- **RANGE-02** — multi-byte UTF-8 correctness through the full compiler pipeline: emoji (4-byte), 名前 (6-byte), 日本語 (9-byte) content with hand-computed expected columns all matching, including the [28,34) second `String` ref after CJK bytes.
- **RANGE-03** — unparseable file still indexes through the full pipeline with exact ends on valid regions and name-length fallback where anchors miss (now proven end-to-end, beyond 08-01's unit proof).

## Verification Results

- Task 1: `swift test --filter IntegrationTests` → 16 tests / 4 suites passed (filter substring also runs Incremental/Multi-Repo/Xcode suites — all green).
- Task 2: `swift test --skip Xcode` → 120 tests / 17 suites passed; `swift test --filter XcodeIntegrationTests` → 5 passed.
- Task 3 wave gate: protected-file diffs quiet — pre-phase suites (SCIPSymbolFormatterTests, ScipIndexMergerTests, MultiRepoMergeIntegrationTests) byte-identical vs PHASE_BASE `9fcc9b1`; PositionMappingTests byte-identical vs WAVE2_BASE `8bb6c42`; PositionMapping.swift diff vs PHASE_BASE is exactly the D3 signature extension (doc comment + parameter + exact-or-approximate branch; approximation math verbatim).
- Partition union: 120 (non-Xcode) + 5 (XcodeIntegration) + 12 (XcodebuildBuildRunner unit) = 137 tests, zero failures.

## Threat Mitigations Applied

- T-08-05 (cache poisoning): second-run byte-identity plus explicit exact-range assertion on the cached document — content-hash keying means the served ranges can only be the ranges that byte-identical content produces.
- T-08-06 (broken-source DoS): the stale-index scenario exercises the worst case directly — the document is never dropped, worst case is approximate ends (asserted both directions).
- T-08-07: no new auth/session/network surface (none added).

## Self-Check: PASSED

Files: Fixtures/UnicodeRangeFixture/Package.swift, Fixtures/UnicodeRangeFixture/Sources/UnicodeRange/main.swift, Fixtures/BrokenSourceFixture/Package.swift, Fixtures/BrokenSourceFixture/Sources/BrokenSource/Recoverable.swift, Tests/scip-swiftTests/IntegrationTests.swift, Tests/scip-swiftTests/IncrementalIntegrationTests.swift — all present. Commits 374837a, a67a535, a9dff2b verified via `git log`. Protected-file gates re-verified before marker cleanup.
