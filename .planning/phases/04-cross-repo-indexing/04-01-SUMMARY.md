---
phase: 04-cross-repo-indexing
plan: 01
subsystem: infra
tags: [scip, indexstore, protobuf, swift-pm, cli]

# Dependency graph
requires:
  - phase: 03-lsp-quality-and-indexing
    provides: SCIPIndexBuilder pipeline, SCIPSymbolFormatter, IndexCommand single-repo index path
provides:
  - "Version field population in SCIP symbol strings (CROSS-03)"
  - "Extracted static IndexCommand.indexOneRepo returning Scip_Index without writing disk"
  - "IndexManyCommand subcommand for multi-repo indexing (CROSS-01, CROSS-02)"
  - "ScipIndexMerger for concatenating/deduplicating multiple Scip_Index objects (CROSS-04 basic path)"
affects: [04-cross-repo-indexing, 05-xcode-fixture]

# Actuals — pairs with the plan's `estimate` to calibrate future estimates.
# Same estimateTokens scale (chars/4 over the realized diff), never a harness token count.
actuals:
  tokens: 4402
  tasks: 2
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns: ["stateless enum namespace for merge logic", "extracted indexOneRepo for reuse across subcommands"]

key-files:
  created:
    - Sources/scip-swift/Commands/IndexManyCommand.swift
    - Sources/scip-swift/SCIPMapping/ScipIndexMerger.swift
    - Tests/scip-swiftTests/ScipIndexMergerTests.swift
  modified:
    - Sources/scip-swift/SCIPMapping/SCIPSymbolFormatter.swift
    - Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift
    - Sources/scip-swift/Commands/IndexCommand.swift
    - Sources/scip-swift/ScipSwiftCommand.swift
    - Tests/scip-swiftTests/SCIPSymbolFormatterTests.swift

key-decisions:
  - "Version defaults to empty string preserving the dot-placeholder behavior for all existing indexes (backward compatible)"
  - "index-many derives per-repo version from repo directory basename — always available, sufficient for cross-repo disambiguation"
  - "ScipIndexMerger is a stateless enum with a static merge function, matching the project convention for stateless mapping logic"

patterns-established:
  - "Stateless enum namespace for pure multi-index transform logic (ScipIndexMerger mirrors SymbolKindMapping/BuildBackendDetector pattern)"
  - "indexOneRepo extraction: command.run() delegates build+index to a static function returning Scip_Index, keeping only serialization+write in run()"

requirements-completed:
  - CROSS-01
  - CROSS-02
  - CROSS-03

# Coverage metadata — one entry per shipped deliverable.
coverage:
  - id: D1
    description: "Version field in SCIP symbol strings is populated when a non-empty version is supplied, with empty default preserving backward compatibility"
    requirement: CROSS-03
    verification:
      - kind: unit
        ref: "Tests/scip-swiftTests/SCIPSymbolFormatterTests.swift#versionFieldPopulated"
        status: pass
      - kind: unit
        ref: "Tests/scip-swiftTests/SCIPSymbolFormatterTests.swift#versionFieldDefaultEmpty"
        status: pass
      - kind: unit
        ref: "Tests/scip-swiftTests/SCIPSymbolFormatterTests.swift#versionFieldSpaceDoubling"
        status: pass
    human_judgment: false
  - id: D2
    description: "ScipIndexMerger merges multiple Scip_Index objects: concatenates documents, deduplicates external symbols, overrides projectRoot, handles empty input"
    requirement: CROSS-04
    verification:
      - kind: unit
        ref: "Tests/scip-swiftTests/ScipIndexMergerTests.swift#documentsConcatenated"
        status: pass
      - kind: unit
        ref: "Tests/scip-swiftTests/ScipIndexMergerTests.swift#externalSymbolsDeduplicated"
        status: pass
      - kind: unit
        ref: "Tests/scip-swiftTests/ScipIndexMergerTests.swift#metadataProjectRootOverridden"
        status: pass
      - kind: unit
        ref: "Tests/scip-swiftTests/ScipIndexMergerTests.swift#emptyInput"
        status: pass
    human_judgment: false
  - id: D3
    description: "IndexManyCommand subcommand accepts variadic repo paths, indexes each repo independently via indexOneRepo, and optionally merges with --merge"
    requirement: CROSS-01
    verification:
      - kind: unit
        ref: "swift build (IndexManyCommand registered as subcommand, compiles with variadic @Argument)"
        status: pass
    human_judgment: true
    rationale: "End-to-end index-many invocation against real repos is validated in Plan 02; unit tests cover the extractable functions, not the CLI shell-out path."

# Metrics
duration: 10min
completed: 2026-08-12
status: complete
---

# Plan 04-01: Cross-Repo Indexing Tracer Summary

**Version field in SCIP symbol strings + extracted indexOneRepo + IndexManyCommand subcommand + basic ScipIndexMerger wiring end-to-end**

## Performance

- **Duration:** ~10 min
- **Tasks:** 2
- **Commits:** 2
- **Files modified:** 8 (6 source + 2 test)

## Accomplishments
- SCIPSymbolFormatter.globalSymbolString accepts a `version` parameter (default `""`) populating the SCIP symbol version field while preserving backward compatibility
- IndexCommand.run() body extracted into static `indexOneRepo(repoPath:output:buildTool:configuration:scheme:cacheDir:indexOnly:symbolVersion:) throws -> Scip_Index`, reused by both index and index-many
- IndexManyCommand subcommand accepts variadic repo paths, indexes each repo independently (CROSS-01/CROSS-02), derives per-repo version from directory basename
- ScipIndexMerger (stateless enum) concatenates documents and deduplicates external symbols across multiple indexes (CROSS-04 basic path)
- 7 new unit tests (3 version-field, 4 merger) covering all new pure functions; all 80 pre-existing tests green

## Task Commits

Each task was committed atomically:

1. **Task 1: Tracer — version field + indexOneRepo extraction + IndexManyCommand + basic ScipIndexMerger wired end-to-end** - `c06c050` (feat)
2. **Task 2: Unit tests for version field behavior and ScipIndexMerger basics** - `11e7749` (test)

## Files Created/Modified
- `Sources/scip-swift/SCIPMapping/SCIPSymbolFormatter.swift` - Added `version: String = ""` parameter to globalSymbolString
- `Sources/scip-swift/SCIPMapping/SCIPIndexBuilder.swift` - Added `symbolVersion` property threaded to all globalSymbolString call sites
- `Sources/scip-swift/Commands/IndexCommand.swift` - Extracted run() body into static indexOneRepo returning Scip_Index
- `Sources/scip-swift/Commands/IndexManyCommand.swift` - New subcommand: variadic repo paths, --merge, per-repo version from basename
- `Sources/scip-swift/SCIPMapping/ScipIndexMerger.swift` - New stateless enum: concatenate documents, dedup external symbols, override projectRoot
- `Sources/scip-swift/ScipSwiftCommand.swift` - Registered IndexManyCommand in subcommands array
- `Tests/scip-swiftTests/SCIPSymbolFormatterTests.swift` - 3 new version-field tests (existing tests unchanged)
- `Tests/scip-swiftTests/ScipIndexMergerTests.swift` - 4 new merger tests (concatenation, dedup, metadata, empty input)

## Decisions Made
- Version defaults to empty string so all existing symbol strings (and .scip indexes) remain byte-identical — backward compatibility by construction
- index-many derives per-repo version from `URL(fileURLWithPath: repoPath).lastPathComponent` — always available, no dependency on package manifests or git tags for the basic tracer
- ScipIndexMerger follows the stateless-enum convention established by SymbolKindMapping/BuildBackendDetector — signals "no constructor needed"

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Cross-repo disambiguation foundation (CROSS-03) is active and tested
- ScipIndexMerger basic path proven; full merge correctness rules (document path prefixing, defined-symbol stripping) expand in Plan 02
- index-many end-to-end invocation against real repos to be validated in Plan 02

---
*Phase: 04-cross-repo-indexing*
*Plan: 01*
*Completed: 2026-08-12*
