---
phase: 08-exact-occurrence-ranges
verified: 2026-08-17T14:05:00Z
status: passed
score: 7/7 must-haves verified
behavior_unverified: 0
overrides_applied: 0
notes: >-
  Two disclosed deviations evaluated and accepted (see Deviation Evaluation):
  wave-1 getter-by-USR lookup (pre-accepted) and wave-2 stale-index RANGE-03
  scenario (empirically forced — verifier reproduced swift build's hard failure
  on syntax errors inside inactive #if branches, exit 1). Partition-union
  coverage is 139 tests, a superset of the SUMMARY's stated 137 (its arithmetic
  omitted the 2 DylibCheckTests skipped by the "Xcode" name filter).
---

# Phase 8: Exact Occurrence Ranges Verification Report

**Phase Goal:** Occurrence ranges are exact — computed from real identifier token extents, correct on Unicode content, with a safe fallback when parsing fails
**Verified:** 2026-08-17T14:05:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Definitions and references both emit end columns from the exact identifier token extent — compound/getter names no longer drift from display-name approximation (SC1, RANGE-01) | ✓ VERIFIED | Independent CLI run (`scip-swift index Fixtures/UnicodeRangeFixture`) decoded from the real `.scip`: `greet` ref L1 [13,18) / def L3 [5,10), `getter:emoji` L0 [4,9) (approximation = 16), `getter:名前` L1 [4,10) (approximation = 17), `getter:name` def [13,17) + interpolation [14,18) asserted in `IntegrationTests.fullPipeline`. Anti-approximation assertions (`!= 16`, `!= 17`, `!= 24`) are symbol-linked by accessor USR (`vg`), not display-name — they fail if the refiner is removed. |
| 2 | Occurrences on lines with multi-byte content report correct columns normalized to UTF-8 byte offsets end-to-end, incl. [28,34) (SC2, RANGE-02) | ✓ VERIFIED | Decoded `.scip` from my own CLI run matches the complete F4 table row-for-row: `String` refs L3 [17,23) **and [28,34)** after 9 CJK bytes, `名前` [4,10) (6 bytes), `emoji` [4,9), interpolation rows L4 [2,3)/[12,16). Byte math independently re-derived (`let 名前 = greet(...)`: greet starts at byte 13 ✓). Unit corpus `SwiftSyntaxRefinerTests.unicodeByteColumns` green (6/6). |
| 3 | Files SwiftSyntax cannot fully parse still index successfully, falling back to name-length ends for affected occurrences (SC3, RANGE-03) | ✓ VERIFIED | Unit: `errorRecovery()` parses genuinely unparseable source (`struct Broken { let x: = }`), asserts `.present` tokens for valid regions + nil in the garbled region. End-to-end: `brokenSourceStillIndexesWithExactEnds` passed (in the 120-test partition run) — document survives, `getter:value` keeps exact [4,9) on the byte-identical region, `getter:tailValue` carries approximate end 20 on anchor miss. Both fallback directions asserted. |
| 4 | Trailing-trivia regression: token end is `positionAfterSkippingLeadingTrivia.utf8Offset + text.utf8.count`, never `endPosition` | ✓ VERIFIED | `SwiftSyntaxRefiner.swift:29-31` implements exactly this with the sanctioned WHY comment; `exactExtentInvariant` test asserts `emoji` ends at 9, not 10 — passed (suite 6/6). |
| 5 | swift-syntax 602.0.0 exact-pinned, resolves, builds against the 6.2.4 toolchain | ✓ VERIFIED | `Package.swift:12` `exact: "602.0.0"`; `Package.resolved` `version: 602.0.0` (no 603+); `swift build` clean on Swift 6.2.4 (verified `swift --version`); debug build completed in 9.5s warm. |
| 6 | Cache-hit second run serves byte-identical exact ranges with no re-parse (research D2) | ✓ VERIFIED | `IncrementalIntegrationTests.cacheHitServesExactRanges` passed: `data1 == data2` plus cached `getter:名前` end == 10 (never 17). Builder code confirms cache hits load the cached document before `makeDocument` (`SCIPIndexBuilder.swift:52-59`), so no re-parse occurs. |
| 7 | Protected regression surface untouched; approximation path behaviorally unchanged | ✓ VERIFIED | `git diff --quiet` clean: `PositionMappingTests.swift` vs WAVE2_BASE `8bb6c42` (IDENTICAL); pre-phase suites (SCIPSymbolFormatter, ScipIndexMerger, MultiRepoMerge, RelationSpike) vs PHASE_BASE `9fcc9b1` (IDENTICAL). `PositionMapping.swift` diff vs PHASE_BASE is exactly the D3 extension: doc comment + `exactEndColumn` parameter + exact-or-approximate branch; approximation math (`approximateTokenLength`, prefix-before-paren) verbatim. |

**Score:** 7/7 truths verified (0 present, behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/scip-swift/SourceRefinement/SwiftSyntaxRefiner.swift` | failable init, one parse per file, line→startCol→endCol map, 1-based lookup | ✓ VERIFIED | 62 lines substantive: line-start byte table w/ binary search, map keyed on ALL tokens, nil-on-miss; retains `source` + `syntaxTree` for Phase 9 reuse; WIRED into `SCIPIndexBuilder.makeDocument:154,178-180` |
| `Sources/scip-swift/SCIPMapping/PositionMapping.swift` | exact-or-approximate `singleLineRange` | ✓ VERIFIED | Anchor math verbatim; exact branch + unchanged approximation branch; default param keeps call sites compiling |
| `Package.swift` / `Package.resolved` | swift-syntax 602.0.0 exact pin | ✓ VERIFIED | `exact: "602.0.0"` + resolved version 602.0.0 |
| `Fixtures/UnicodeRangeFixture/*` | F4 byte-exact source through real SwiftPM build | ✓ VERIFIED | Lines 0-4 byte-exact (`emoji`/`名前`/`greet`/interpolation); discardable uses (`_ = emoji`, `_ = 名前`) after line 4 so hand-computed columns hold; built through the same `SwiftPMBuildRunner` path |
| `Fixtures/BrokenSourceFixture/*` | stale-index corruption scenario | ✓ VERIFIED | Valid `Recoverable.swift` committed; test corrupts on disk post-build and self-restores via `defer` |
| `Tests/scip-swiftTests/SwiftSyntaxRefinerTests.swift` | 6-test unit corpus | ✓ VERIFIED | All F4 rows, trailing-trivia, error recovery, anchor-miss, unreadable-path — 6/6 passed |
| `Tests/scip-swiftTests/PositionMappingTests.swift` | exact/approximate contract | ✓ VERIFIED | 5/5 passed; byte-identical to WAVE2_BASE |
| `README.md` | exact-range + binary-size trade-off documented | ✓ VERIFIED | Known limitations: exact token extents w/ approximation fallback; ~7 → ~24.5 MB accepted trade-off stated |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `Package.swift` exact pin | `Package.resolved` | `swift package resolve` | ✓ WIRED | 602.0.0 resolved; executable target carries SwiftSyntax + SwiftParser products |
| `SwiftSyntaxRefiner.exactEndColumn` | `PositionMapping.singleLineRange` | builder occurrence loop | ✓ WIRED | `SCIPIndexBuilder.swift:154` constructs refiner; `:178-180` passes `.map(Int32.init)` lookup result |
| `makeDocument` cache-hit branch | cached exact ranges | CacheStore content-hash | ✓ WIRED | Cache check precedes `makeDocument`; byte-identity + exact-end assertions prove the served ranges |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| `SwiftSyntaxRefiner` | `tokenEndColumns` | `Parser.parse` over real file bytes | Yes — decoded `.scip` ranges from a real CLI run match hand-computed F4 | ✓ FLOWING |
| `PositionMapping` | `endCharacter` | refiner lookup or fallback | Yes — both branches exercised end-to-end | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| CLI emits exact F4 ranges (RANGE-01/02) | `scip-swift index Fixtures/UnicodeRangeFixture` + protobuf decode of `.scip` field 8 | 17 occurrences decoded; every F4 row matches incl. [28,34) | ✓ PASS |
| Full non-Xcode partition | `swift test --skip Xcode` | 120 tests / 17 suites passed | ✓ PASS |
| Xcode partitions | `swift test --filter XcodeIntegrationTests --filter XcodebuildBuildRunnerTests` | 17 tests / 2 suites passed | ✓ PASS |
| DylibCheck partition (skipped by name filter) | `swift test --filter DylibCheckTests` | 3 tests passed | ✓ PASS |
| swift build fails on syntax error inside `#if false` (deviation claim) | fresh SwiftPM package, `struct Broken { let x: = }` inside `#if false` | exit 1, 4 `error:` diagnostics | ✓ PASS — executor's claim reproduced |
| New unit suites | `swift test --filter SwiftSyntaxRefinerTests` / `PositionMappingTests` | 6/6 and 5/5 passed | ✓ PASS |

**Partition union:** 120 (non-Xcode) + 17 (Xcode suites) + 2 (DylibCheck tests skipped by the `--skip Xcode` name filter) = **139/139 tests enumerated and passed** via `--list-tests` cross-check. The SUMMARY's "137 total" under-counts by 2 — its arithmetic (120+5+12) omitted `DylibCheckTests/containsXcode()` and `/containsXcodeSelect()`, which the name filter silently skips. Coverage is complete; the count is off. (INFO)

### Probe Execution

No probes declared in PLAN/SUMMARY for this phase. SKIPPED.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|---------------------|----------|
| RANGE-01 | 08-01, 08-02 | Exact identifier extents for defs and refs; no display-name drift | ✓ SATISFIED | Decoded `.scip` + getter drift proofs (9≠16, 10≠17, 17≠24) symbol-linked by accessor USR |
| RANGE-02 | 08-01, 08-02 | UTF-8 byte columns on multi-byte lines, fixture test | ✓ SATISFIED | Complete F4 table from a real compiler build incl. [28,34); unit corpus green |
| RANGE-03 | 08-01, 08-02 | Unparseable files still index with name-length fallback | ✓ SATISFIED | Unit error-recovery corpus + e2e stale-index scenario asserting both fallback directions |

No orphaned requirements: REQUIREMENTS.md maps exactly RANGE-01..03 to Phase 8, all claimed by both plans.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | No TBD/FIXME/XXX/TODO/HACK/placeholder markers in any phase-modified file | — | — |

The two WHY comments in `SwiftSyntaxRefiner.swift` (trailing-trivia invariant; 1-based→0-based lookup) are the plan-sanctioned sites. No scratch markers (`PHASE_BASE`/`WAVE2_BASE` files) remain on disk.

### Deviation Evaluation

**1. Wave-1: getter located by USR (`...SSvg`) instead of display name `getter:name`.** Pre-accepted. Independently confirmed necessary: document symbol display names are demangled (`MiniSwiftPackage.Greeter.name`), so a display-name filter matches nothing. The USR-fragment lookup is strictly more precise — the drift assertions remain load-bearing.

**2. Wave-2: RANGE-03 e2e uses build-valid → corrupt-on-disk → index instead of a committed broken file.** **Accepted, with the executor's premise independently reproduced.** I built a fresh SwiftPM package with `struct Broken { let x: = }` inside `#if false`: `swift build` emits 4 `error:` diagnostics and exits 1. Since `SwiftPMBuildRunner` throws on non-zero exit, a committed unparseable file can never produce index-store occurrences to refine — the plan's original premise was unachievable. The stale-index alternative genuinely exercises the fallback contract in both directions: the refiner parses genuinely-unparseable on-disk content (the corruption contains `struct { let x: = }`), the byte-identical line-0 anchor hits the error-recovery token map (exact [4,9)), and the stale `tailValue` anchor misses (approximate 20 = 4 + `"getter:tailValue".utf8.count`). That is exactly RANGE-03's contract: exact on valid regions, approximate on anchor miss, document never dropped. The refiner-level `errorRecovery()` unit test additionally covers a directly-unparseable source, so the deviation removes no coverage that is achievable.

**Note (INFO):** RANGE-03's parenthetical "macro-expanded code" case has no dedicated macro fixture. Structurally, macro usages anchor at original source positions the refiner parses, and any miss routes through the proven anchor-miss fallback; the unparseable-source case is the real fallback trigger and is covered both levels. No action required.

### Human Verification Required

None. All behavior-dependent truths have first-party behavioral evidence (independent CLI run + decoded `.scip`, partition test runs, empirical reproduction of the deviation premise).

### Gaps Summary

No gaps. All three roadmap success criteria are observably true in the codebase with independently-decoded `.scip` evidence, the full test partition union (139 tests) passes, protected files are byte-identical to their gate bases, all eight phase commits are reachable from HEAD, and both disclosed deviations check out under independent scrutiny.

**Bookkeeping (expected next step, not a gap):** REQUIREMENTS.md (RANGE-01..03 rows still `[ ]` / `pending`), ROADMAP.md (Phase 8 top-level + plans checkboxes still unchecked), and STATE.md (still shows phase 8, `stopped_at: Completed 07-02-PLAN.md`) have not been flipped. This matches the repo convention — Phase 7's flip (`2a347e6`) landed after its verification report (`f8f6489`), so the orchestrator performs bookkeeping post-verification.

---

_Verified: 2026-08-17T14:05:00Z_
_Verifier: gsd-verifier_
