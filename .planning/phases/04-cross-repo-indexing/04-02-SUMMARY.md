---
phase: 04-cross-repo-indexing
plan: 02
subsystem: scip-mapping
tags: [scip, protobuf, merge, integration-test, fixtures]

# Dependency graph
requires:
  - phase: 04-cross-repo-indexing
    plan: 01
    provides: ScipIndexMerger basic merge, SCIPIndexBuilder symbolVersion, IndexManyCommand
provides:
  - "Merge correctness rules: external symbol stripping, document path prefixing, relationship target preservation (CROSS-04, CROSS-05)"
  - "Cross-repo fixture packages for multi-repo testing"
  - "Multi-repo merge integration test (TEST-05)"
affects: []

# Actuals — pairs with the plan's `estimate` to calibrate future estimates.
actuals:
  tokens: 3800
  tasks: 2
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns: ["structural invariant assertions matching scip lint rules for in-process validation"]

key-files:
  created:
    - Fixtures/CrossRepoPackageA/Package.swift
    - Fixtures/CrossRepoPackageA/Sources/CrossRepoPackageA/Shared.swift
    - Fixtures/CrossRepoPackageB/Package.swift
    - Fixtures/CrossRepoPackageB/Sources/CrossRepoPackageB/Consumer.swift
    - Tests/scip-swiftTests/MultiRepoMergeIntegrationTests.swift
  modified:
    - Tests/scip-swiftTests/ScipIndexMergerTests.swift

key-decisions:
  - "ScipIndexMerger already had all correctness rules implemented from Plan 01 (repoIdentifiers prefixing, definedSymbol stripping, dedup, sorting) — Plan 02 added test coverage, not new logic"
  - "Cross-repo fixtures build independently with no real Swift package dependency — the cross-repo reference is simulated at the SCIP merge level"
  - "Integration test validates structural invariants in-process (no scip lint binary dependency) — checks mirror bothLocalAndExternalSymbolError, duplicateDocumentWarning, and missingSymbolForOccurrenceError"

patterns-established:
  - "In-process structural invariant checks mirroring scip lint rules as a fallback when the scip CLI binary is not installed"
  - "Two-fixture cross-repo integration test pattern: build each fixture independently with distinct symbolVersion, merge, validate combined structural correctness"

requirements-completed:
  - CROSS-04
  - CROSS-05
  - TEST-05

# Coverage metadata — one entry per shipped deliverable.
coverage:
  - id: D1
    description: "External symbols defined in any merged document are stripped from externalSymbols (prevents bothLocalAndExternalSymbolError)"
    requirement: CROSS-04
    verification:
      - kind: unit
        ref: "Tests/scip-swiftTests/ScipIndexMergerTests.swift#stripsExternalsDefinedInDocuments"
        status: pass
      - kind: integration
        ref: "Tests/scip-swiftTests/MultiRepoMergeIntegrationTests.swift#mergedIndexStructuralValidity"
        status: pass
    human_judgment: false
  - id: D2
    description: "External symbols not defined in any document are preserved (relationship targets survive — prevents missingSymbolInRelationshipError)"
    requirement: CROSS-05
    verification:
      - kind: unit
        ref: "Tests/scip-swiftTests/ScipIndexMergerTests.swift#preservesUndefinedExternalSymbols"
        status: pass
    human_judgment: false
  - id: D3
    description: "Document relativePaths are prefixed with repo identifier to prevent duplicateDocumentWarning"
    requirement: CROSS-04
    verification:
      - kind: unit
        ref: "Tests/scip-swiftTests/ScipIndexMergerTests.swift#distinctPathsForSameRelativePath"
        status: pass
      - kind: unit
        ref: "Tests/scip-swiftTests/ScipIndexMergerTests.swift#relativePathPrefixedWithRepoIdentifier"
        status: pass
      - kind: integration
        ref: "Tests/scip-swiftTests/MultiRepoMergeIntegrationTests.swift#mergedIndexStructuralValidity"
        status: pass
    human_judgment: false
  - id: D4
    description: "External symbols are deduplicated and sorted across all input indexes"
    requirement: CROSS-04
    verification:
      - kind: unit
        ref: "Tests/scip-swiftTests/ScipIndexMergerTests.swift#deduplicatesAcrossThreeIndexes"
        status: pass
      - kind: unit
        ref: "Tests/scip-swiftTests/ScipIndexMergerTests.swift#externalSymbolsSortedBySymbol"
        status: pass
    human_judgment: false
  - id: D5
    description: "Integration test proves two-repo build → index → merge → structural validation produces a valid combined index"
    requirement: TEST-05
    verification:
      - kind: integration
        ref: "Tests/scip-swiftTests/MultiRepoMergeIntegrationTests.swift#mergedIndexStructuralValidity"
        status: pass
    human_judgment: false

# Metrics
duration: 12min
completed: 2026-08-13
status: complete
---

# Plan 04-02: Merge Correctness Rules Summary

**6 scip-lint-matching correctness unit tests + 2 cross-repo fixture packages + multi-repo merge integration test**

## Performance

- **Duration:** ~12 min
- **Tasks:** 2
- **Commits:** 3
- **Files created:** 5 (4 fixtures + 1 test)
- **Files modified:** 1 (ScipIndexMergerTests.swift — appended, existing 4 tests unchanged)
- **Total test count:** 94 (was 87; +6 unit +1 integration)

## Accomplishments
- Added 6 correctness-rule unit tests to ScipIndexMergerTests covering all three scip lint pitfalls from the research: bothLocalAndExternalSymbolError (external stripping), duplicateDocumentWarning (path prefixing), missingSymbolInRelationshipError (target preservation), plus deduplication across 3+ indexes and sort verification
- Created two minimal fixture packages (CrossRepoPackageA with `SharedType`, CrossRepoPackageB with `Consumer`) that build independently with no real Swift package dependency — the cross-repo reference is simulated at the merge level
- Created MultiRepoMergeIntegrationTests (TEST-05) following the IntegrationTests.swift no-mocks pattern: builds both fixtures with real SwiftPMBuildRunner, indexes each with distinct symbolVersion, merges with repoIdentifiers, and validates structural invariants (document count, prefixed paths, no duplicate paths, no bothLocalAndExternal, all occurrences resolve)
- All 94 tests pass with zero regressions

## Task Commits

Each task was committed atomically:

1. **Task 1: 6 merge correctness unit tests** - `29444f8` (test)
2. **Task 2A: Cross-repo fixture packages** - `5b41fe1` (test)
3. **Task 2B: Multi-repo merge integration test** - `cd63afc` (test)

## Files Created/Modified
- `Tests/scip-swiftTests/ScipIndexMergerTests.swift` - Added 6 tests: stripsExternalsDefinedInDocuments, preservesUndefinedExternalSymbols, distinctPathsForSameRelativePath, relativePathPrefixedWithRepoIdentifier, deduplicatesAcrossThreeIndexes, externalSymbolsSortedBySymbol
- `Fixtures/CrossRepoPackageA/Package.swift` - Minimal package, single target, swift-tools-version 6.2
- `Fixtures/CrossRepoPackageA/Sources/CrossRepoPackageA/Shared.swift` - Public struct `SharedType` with property, init, method
- `Fixtures/CrossRepoPackageB/Package.swift` - Minimal package, single target, swift-tools-version 6.2
- `Fixtures/CrossRepoPackageB/Sources/CrossRepoPackageB/Consumer.swift` - Public struct `Consumer` with property, init, method
- `Tests/scip-swiftTests/MultiRepoMergeIntegrationTests.swift` - Integration test: build both fixtures → index with distinct symbolVersion → merge → validate structural invariants

## Decisions Made
- No merge logic changes were needed — Plan 01's ScipIndexMerger already implemented all correctness rules (repoIdentifiers prefixing, definedSymbol stripping, dedup via dictionary, sort). Plan 02 added test coverage to prove correctness.
- Fixtures use different module names (CrossRepoPackageA/CrossRepoPackageB) so the symbolVersion parameter genuinely disambiguates symbol strings across repos.
- Integration test validates in-process structural invariants rather than shelling out to `scip lint` — the structural checks mirror the exact lint rules (no bothLocalAndExternal, no duplicate documents, all occurrences resolve to a SymbolInformation), providing authoritative validation without a binary dependency.

## Deviations from Plan

None — plan executed exactly as written. The merge implementation required zero changes.

## Issues Encountered
None

## User Setup Required
None — no external service configuration or binary installation required.

## Next Phase Readiness
- Cross-repo merge correctness (CROSS-04, CROSS-05) is fully tested at unit and integration level
- TEST-05 validates the end-to-end multi-repo flow with real fixtures and no mocks
- Phase 04 (Cross-Repo Indexing) is functionally complete: version field disambiguation, index-many subcommand, and correct merge all delivered

---
*Phase: 04-cross-repo-indexing*
*Plan: 02*
*Completed: 2026-08-13*
