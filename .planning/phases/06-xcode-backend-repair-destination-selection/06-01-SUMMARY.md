---
phase: 06-xcode-backend-repair-destination-selection
plan: 01
subsystem: build-backend-dispatch
tags: [xcodebuild, dispatch, integration-tests, index-command]
requires:
  - BuildBackendDetector (.swiftpm/.xcodebuild detection)
  - XcodebuildBuildRunner / XcodeProjectLocator (pre-existing, unchanged)
  - SwiftPMBuildRunner (pre-existing, unchanged)
provides:
  - Shared produceIndexStore(tool:repoPath:configuration:scheme:scratchPath:) dispatch helper in IndexCommand
  - End-to-end xcodebuild dispatch on both cache branches of indexOneRepo (REPAIR-01)
affects:
  - "scip-swift index <xcode-repo>" (temp path and --cache-dir path now reach the xcodebuild backend)
tech-stack:
  added: []
  patterns:
    - "single switch-tool dispatch point shared by both indexOneRepo cache branches"
key-files:
  created: []
  modified:
    - Sources/scip-swift/Commands/IndexCommand.swift
    - Tests/scip-swiftTests/XcodeIntegrationTests.swift
decisions:
  - "Derived data placed beside the scratch dir (scratchPath parent + /derived-data): temp runs put it under the temp work dir, persistent-cache runs under the cache dir, mirroring the original workDirectory/derived-data convention from 1c5ba8f"
  - "Helper returns indexStorePath as String rather than IndexStoreBuildResult — both call sites only consume the path"
metrics:
  duration: 21m
  completed: 2026-08-16
actuals:
  tokens: 1200   # ~4.7k diff chars / 4
  tasks: 2
  commits: 4
status: complete
requirements: [REPAIR-01]
---

# Phase 6 Plan 1: Xcode Backend Dispatch Repair Summary

Restores the `.xcodebuild` dispatch lost in `0cdefd7` by extracting one shared `switch tool` helper called from both `indexOneRepo` cache branches, proven end-to-end by two real-xcodebuild integration tests against `Fixtures/XcodeTestProject`.

## What Was Built

- **Shared dispatch helper** `produceIndexStore(tool:repoPath:configuration:scheme:scratchPath:)` in `IndexCommand.swift` (private static, returns the produced `indexStorePath` as `String`):
  - `.swiftpm` — moves the existing `SwiftPMBuildRunner(repoPath:configuration:scratchPath:)` construction verbatim.
  - `.xcodebuild` — restores the code lost in `0cdefd7` (verbatim from `1c5ba8f`): `XcodeProjectLocator.workspaceOrProjectArguments` → `resolveScheme` → `XcodebuildBuildRunner` with `derivedDataPath` set to `derived-data` beside the scratch directory (`scratchPath`'s parent), so temp runs keep derived data under the temp work directory and persistent-cache runs under the cache dir.
- **Both cache branches rewired** — the no-cache else-branch (Task 1) and the persistent-cache build branch (Task 2) now call the one helper; the dispatch bug cannot survive in either path.
- **Two integration tests** in `XcodeIntegrationTests` (Swift Testing, real `xcodebuild`, no mocks):
  1. `"indexOneRepo builds an Xcode fixture through the xcodebuild backend"` — no cache flags → temp branch, asserts `documents.count > 0` with a Swift first document.
  2. `"indexOneRepo with --cache-dir also builds an Xcode fixture through xcodebuild"` — fresh temp `cacheDir` (defer-cleaned), asserts documents > 0 **and** that `cacheDir/derived-data` exists, pinning the cache-branch layout convention.
- The `--index-only` path was deliberately untouched (`SwiftPMBuildRunner.findIndexStore` asymmetry is out of scope this phase, per plan).

## Commits

| Task | Commit | Type | Content |
|------|--------|------|---------|
| 1 RED | `e74d16b` | test | Failing temp-branch dispatch test |
| 1 GREEN | `9bcf168` | feat | Shared helper + xcodebuild case + temp-branch rewire |
| 2 RED | `028c35a` | test | Failing cache-branch dispatch test |
| 2 GREEN | `9200e70` | feat | Persistent-cache branch through shared helper |

## Test Results

| Command | Result |
|---------|--------|
| `swift test --filter XcodeIntegrationTests` (per-task GREEN, after Task 2) | 3/3 passed (21s) |
| `swift test --filter IntegrationTests` (regression guard) | 8/8 passed across 4 matched suites (`Xcode Integration`, `XcodebuildBuildRunner arguments`, `Incremental Indexing`, `Multi-Repo Merge`) |
| `swift test --skip IntegrationTests` (unit suites) | 89/89 passed, 12 suites |
| `swift test --filter Xcode` | 12/12 passed, 3 suites |
| `swift test --filter MultiRepo\|Incremental` | 4/4 passed, 2 suites |
| `swift build` | green; `IndexManyCommand` and all `indexOneRepo` call sites compile unchanged |

RED confirmations: Task 1 RED failed with `documents.count → 0` after 55.8s (SwiftPM runner built against the fixture dir); Task 2 RED failed with `documents.count → 0` and missing `derived-data` under the cache dir after 38.5s.

**Note on the literal monolithic `swift test`:** a single full-suite invocation repeatedly exceeded the execution wrapper's 300s hard timeout (killed mid-run; integration suites do real `swift build`/`xcodebuild` against fixtures). Every suite in the repo was run and passed green via the filter/skip partition above, whose union covers 100% of the test targets — no suite was skipped or weakened. The phase gate `swift test` should be re-run in a shell without the timeout constraint at phase-verify time.

## Success Criteria

- [x] `indexOneRepo` on `Fixtures/XcodeTestProject` with no cache flags returns an index with documents via the xcodebuild backend
- [x] `indexOneRepo` with a `cacheDir` also dispatches to XcodebuildBuildRunner, derived data under the cache dir
- [x] SwiftPM repos keep dispatching to SwiftPMBuildRunner — existing `IntegrationTests` and cache suites green
- [x] Exactly one switch-tool dispatch helper, called from both cache branches of `indexOneRepo`
- [x] `swift build` green; helper is additive to `IndexManyCommand`

## Deviations from Plan

None — plan executed exactly as written. Two execution-environment notes (not plan deviations):

1. The plan's RED expectation for Task 1 ("fails with a SwiftPM build error") was directionally right but the observed failure mode was softer: `swift build` inside the fixture directory walks up the directory tree, finds the scip-swift `Package.swift` at the repo root, and *succeeds* building the wrong package — yielding an index with 0 fixture documents rather than a thrown error. Same RED semantics (test failed before fix, passed after); documented here because "misleading SwiftPM error" per the plan is even more misleading than described.
2. The full-suite monolith run hit the tooling timeout as described under Test Results; coverage was achieved via partitioned runs.

## Threat Model

No new threat surface. Restored code passes existing paths through the existing `SubprocessRunner` argument arrays — no shell string building introduced (matches dispositions T-06-01 accept, T-06-02 accept).

## Known Stubs

None — no placeholders, TODOs, or unwired paths were introduced.

## Self-Check: PASSED

All four commits (`e74d16b`, `9bcf168`, `028c35a`, `9200e70`) present in git log; all claimed files exist on disk; `SwiftPMBuildRunner(` constructed exactly once (inside the shared helper) — both `indexOneRepo` cache branches route through `produceIndexStore`.
