---
phase: 08-exact-occurrence-ranges
plan: 01
subsystem: source-refinement
tags: [swift-syntax, occurrence-ranges, utf8, exact-extends]
requires:
  - "IndexStoreDB occurrence anchors (Phase 3)"
  - "PositionMapping singleLineRange approximation (Phase 3)"
provides:
  - "SwiftSyntaxRefiner exact token-extent map keyed line -> byte startCol -> byte endCol"
  - "PositionMapping.singleLineRange(exactEndColumn:) exact-or-approximate contract"
  - "swift-syntax 602.0.0 exact pin"
affects:
  - "SCIPIndexBuilder.makeDocument occurrence loop (one refiner per non-cached document)"
  - "README Known limitations (occurrence ranges + binary size)"
tech-stack:
  added:
    - "swift-syntax 602.0.0 (SwiftSyntax + SwiftParser products, exact pin)"
  patterns:
    - "self-computed UTF-8 line-start byte table (never SourceLocationConverter)"
    - "nil-on-miss refinement fallback to existing approximation"
key-files:
  created:
    - Sources/scip-swift/SourceRefinement/SwiftSyntaxRefiner.swift
    - Tests/scip-swiftTests/SwiftSyntaxRefinerTests.swift
    - Tests/scip-swiftTests/PositionMappingTests.swift
  modified:
    - Package.swift
    - Package.resolved
    - Sources/scip-swift/SCIPMapping/PositionMapping.swift
    - Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift
    - Tests/scip-swiftTests/IntegrationTests.swift
    - README.md
decisions:
  - "Map keyed on ALL tokens (operators, init, attributes), not just identifiers — preserves the measured 100% anchor hit rate"
  - "Line/column math from a self-computed line-start table over Array(source.utf8); SourceLocationConverter column basis unverified so it is never used"
  - "Refiner stores source + syntax tree for Phase 9 doc extraction from the same parse; no docs extracted yet"
  - "No version bump — 0.3.0 unreleased; content-hash cache self-heals per file"
metrics:
  duration: "70m"
  completed: "2026-08-17"
status: complete
actuals:
  tokens: 22000
  tasks: 3
  commits: 3
---

# Phase 8 Plan 01: Exact Occurrence Ranges Summary

One-liner: SwiftSyntaxRefiner turns IndexStoreDB anchor-only occurrences into exact identifier-token end columns (UTF-8 byte offsets) via a single swift-syntax parse per file, with the old name-length approximation kept as a nil-fallback.

## What Was Built

- **swift-syntax 602.0.0 exact pin** — `.package(url: ..., exact: "602.0.0")` with `SwiftSyntax` + `SwiftParser` products on the executable target; `Package.resolved` pins 602.0.0 exactly (verified no 603+ drift); cold build cost accepted per research D1/F6. README "Known limitations" now documents exact ranges with approximation-as-fallback and the ~7 → ~24.5 MB binary trade-off.
- **`Sources/scip-swift/SourceRefinement/SwiftSyntaxRefiner.swift`** — failable `init?(filePath:)` (nil on read failure), one `Parser.parse` per file, line-start byte table computed over `Array(source.utf8)`, `tokenEndColumns: [Int: [Int: Int]]` keyed on ALL tokens with `end = positionAfterSkippingLeadingTrivia.utf8Offset + token.text.utf8.count` (never `endPosition` — trailing trivia, sanctioned WHY-comment in place). `exactEndColumn(line:utf8Column:)` takes IndexStoreDB's 1-based values, subtracts 1 on lookup, returns nil on any miss. Source + syntax tree retained for Phase 9 docs (same parse).
- **`PositionMapping.singleLineRange(location:displayName:exactEndColumn: Int32? = nil)`** — anchor 1-based→0-based math verbatim from before; exact end used when non-nil, existing `approximateTokenLength` path unchanged otherwise (defaulted parameter, no other call sites existed).
- **`SCIPIndexBuilder.makeDocument`** — constructs the refiner once after the occurrences guard; passes `refiner?.exactEndColumn(...).map(Int32.init)` into `singleLineRange`. Cache-hit branch untouched (skips `makeDocument`, so cached documents carry already-exact ranges with no re-parse).
- **Test corpus** — `SwiftSyntaxRefinerTests` (6 tests: F4 Unicode byte-column rows, exact-extent/trailing-trivia invariant `emoji` ends 9 not 10, line-table round-trip, error-node token recovery with garbled-region miss, anchor-miss nil, unreadable-path nil init) and `PositionMappingTests` (5 tests: exact-when-present, approximation-byte-identical-when-nil, 0-based math, compound-name prefix, clamping). Tracer in `IntegrationTests.fullPipeline`: the `getter:name` occurrences (USR `s:16MiniSwiftPackage7GreeterV4nameSSvg`) assert exact `[13,17)` on the property definition line and `[14,18)` inside the string interpolation — the approximation would have produced 24 (+7 drift, F3a).

## How to Verify

```sh
swift test --filter SwiftSyntaxRefinerTests   # 6 tests
swift test --filter PositionMappingTests      # 5 tests
swift test --filter IntegrationTests          # tracer + regression
swift test --skip Xcode                       # 117 tests / 17 suites — full wave gate
```

## Commits

| Task | Commit | Type | Summary |
|------|--------|------|---------|
| 1 | `fe4d426` | chore | swift-syntax 602.0.0 exact pin + README trade-off note |
| 2 (RED) | `dfab00a` | test | failing refiner + position-mapping suites |
| 2 (GREEN) | `ce87574` | feat | SwiftSyntaxRefiner + exactEndColumn plumbing + tracer assertion |

## TDD Gate Compliance

RED (`dfab00a`) precedes GREEN (`ce87574`); RED failed to compile on exactly the two expected errors (`cannot find type 'SwiftSyntaxRefiner'`, `extra argument 'exactEndColumn'`) before any implementation existed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Tracer USR filter and hand-computed error-node expectations corrected**
- **Found during:** Task 2 RED/GREEN
- **Issue:** (a) The plan suggested identifying the getter by display name `getter:name`, but symbol display names in the document are demangled (`MiniSwiftPackage.Greeter.name`), so no occurrence matched — an empirical IndexStoreDB probe of the fixture showed the getter rides on USR `...4nameSSvg` with anchors at line 2 col 14 and line 9 col 15. (b) Three hand-computed expectations in the RED suite were off by one in my first draft (`Broken` is 6 bytes not 7; `alsoOk` 6 not 7; col 12 of line 2 is the `=` operator token, which legitimately maps).
- **Fix:** Tracer matches the getter by USR substring and asserts both exact extents ([13,17) definition, [14,18) interpolation); the three unit expectations were corrected with byte arithmetic matching the verified invariant `start + text.utf8.count`.
- **Files modified:** Tests/scip-swiftTests/IntegrationTests.swift, Tests/scip-swiftTests/SwiftSyntaxRefinerTests.swift
- **Commit:** `ce87574`

No other deviations — plan executed as written (PHASE_BASE captured, protected-file gates passed, sanctioned comments only).

## Requirements Delivered

- **RANGE-01** — exact identifier-token ends for definitions and references; `getter:name` drift case (+7) asserted end-to-end in a real `.scip` (tracer, `ce87574`).
- **RANGE-02** — F4 Unicode rows green at unit level (`emoji`/`名前`/`greet`/`name`/both `String` refs at [28,34)); all columns UTF-8 byte offsets from the self-computed line-start table.
- **RANGE-03** — broken source still yields a usable token map (`.present` tokens for valid regions); anchor-miss and unreadable-file both return nil and fall back to today's approximation byte-for-byte.

## Verification Results

- `swift package resolve` → Package.resolved pins 602.0.0 exactly; `swift build` clean.
- `swift test --filter SwiftSyntaxRefinerTests` → 6/6 passed.
- `swift test --filter PositionMappingTests` → 5/5 passed.
- `swift test --filter IntegrationTests` → passed (tracer + all regression rows).
- `swift test --filter RelationSpikeTests` → 3/3 passed.
- Task 3 wave gate: `swift test --skip Xcode` → **117 tests / 17 suites passed**; protected-file diffs quiet against PHASE_BASE (pre-phase suites) and HEAD (PositionMappingTests).

## Threat Mitigations Applied

- T-08-01 (parser DoS): non-throwing `Parser.parse`, nil-init on unreadable file, misses fall back — no path throws or drops an occurrence.
- T-08-02 (supply chain): exact pin 602.0.0 in Package.resolved (verified), no `from:` range.
- T-08-03 (build/binary cost): accepted and documented in README Known limitations.
- T-08-04: no new network/auth surface (none added).

## Self-Check: PASSED

Files: Package.swift, Package.resolved, README.md, SwiftSyntaxRefiner.swift, PositionMapping.swift, SCIPIndexBuilder.swift, SwiftSyntaxRefinerTests.swift, PositionMappingTests.swift, IntegrationTests.swift — all present. Commits fe4d426, dfab00a, ce87574 verified via `git log`. Protected-file gates re-run after final commit: PHASE_BASE_GATE_OK, HEAD_GATE_OK.
