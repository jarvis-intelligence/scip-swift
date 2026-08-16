---
phase: 06-xcode-backend-repair-destination-selection
plan: 02
subsystem: xcodebuild-backend
tags: [xcodebuild, destination, cli, error-handling]
requires: ["06-01"]
provides: ["--destination CLI flag", "destination-gated failure hint"]
affects: [Sources/scip-swift/Build/XcodebuildBuildRunner.swift, Sources/scip-swift/Build/BuildError.swift, Sources/scip-swift/Commands/IndexCommand.swift]
tech-stack:
  added: []
  patterns: ["defaulted-param threading to keep positional call sites compiling", "var-default stored property for optional memberwise-init param"]
key-files:
  created: []
  modified:
    - Sources/scip-swift/Build/XcodebuildBuildRunner.swift
    - Sources/scip-swift/Build/BuildError.swift
    - Sources/scip-swift/Commands/IndexCommand.swift
    - Tests/scip-swiftTests/XcodebuildBuildRunnerTests.swift
    - Tests/scip-swiftTests/XcodeIntegrationTests.swift
decisions:
  - "destination as var-default stored property (not let-optional) so every existing call site compiles without edits"
  - "gate the new error case strictly on destination != nil rather than string-matching xcodebuild output — marker strings vary across Xcode versions"
metrics:
  duration: 18m
  completed: 2026-08-16
actuals:
  tokens: 3222
  tasks: 3
  commits: 6
status: complete
---

# Phase 6 Plan 02: xcodebuild --destination Selection & Failure Hint Summary

Opt-in `--destination <spec>` for the xcodebuild backend: spliced into the pure argument list, threaded from the CLI, with a destination-gated `xcodebuildDestinationFailed` error carrying full output plus a copyable `-showdestinations` hint.

## What Was Built

- **`XcodebuildBuildRunner.destination: String? = nil`** (var-default form) — the synthesized memberwise init keeps every pre-existing call site compiling without edits. Non-nil destination inserts `["-destination", spec]` immediately before `-derivedDataPath`; nil leaves the list byte-identical (guarded by a dedicated unit test, and the 7 pre-existing assertions stayed green with zero edits).
- **`BuildError.xcodebuildDestinationFailed(exitCode:output:hintCommand:)`** — description embeds the full untruncated output (mirroring `.buildFailed`'s style) followed by the hint command. Thrown from `produceIndexStore()` strictly when `destination != nil` and exit code != 0; nil-destination failures keep the unchanged `.buildFailed` path. No string-matching of xcodebuild error text.
- **CLI threading** — `@Option --destination` on `IndexCommand` (help text recommends `generic/platform=iOS Simulator`), defaulted parameter on `indexOneRepo` and the 06-01 dispatch helper, forwarded into the runner from both cache branches. `IndexManyCommand` compiled with **zero edits** via the defaulted parameter.
- The stale lines 24-31 comment block (which justified no-destination defaults) was rewritten for the opt-in world, preserving the GatherProvisioningInputs rationale.

## Task Execution Record

| Task | Name | RED commit | GREEN commit |
|------|------|-----------|--------------|
| 1 | destination property + argument splice (REPAIR-02) | db4ac48 | f65512e |
| 2 | xcodebuildDestinationFailed error case (REPAIR-03) | d542e24 | 6991ffc |
| 3 | CLI threading + live destination runs (REPAIR-02/03 e2e) | 2cfff1e | 34a6fc9 |

Every TDD task: failing test written first, compile failure confirmed as RED, then implementation, then green.

## Verification

- `swift test --filter XcodebuildBuildRunnerTests` — 12/12 green (<1s): 7 pre-existing + 3 splice tests + 2 description tests.
- `swift test --filter Xcode` — 19/19 green across 3 suites (DylibCheck, XcodebuildBuildRunner, Xcode Integration), real xcodebuild: macOS destination success (27s), bogus-destination failure with hint (63s — matches research's predicted device-matching timeout).
- `swift test --filter IntegrationTests` — 10/10 green in 4 suites (filter is a substring match; covers both the SwiftPM `IntegrationTests` and `XcodeIntegrationTests` suites — SwiftPM path unregressed).
- **Full-suite proof via partition** (bare `swift test` exceeds the 300s command ceiling, as flagged in wave 1): `swift test --list-tests` enumerates 104 tests. Partition 1 `--skip Xcode` ran 85/85 green (14 suites); Partition 2 `--filter Xcode` ran 19/19 green (3 suites). 85 + 19 = 104, zero overlap, union = full enumeration. **All 104 tests green.**
- CLI surface: `scip-swift index --help` shows `--destination` with the recommended default.

## Requirements Covered

| ID | Description | Status |
|----|-------------|--------|
| REPAIR-02 | `--destination <spec>` flag; nil default preserves behavior | ✅ unit + integration verified |
| REPAIR-03 | Failed destination builds surface `-showdestinations` hint | ✅ description tests + live bogus-destination run |

## Deviations from Plan

None — plan executed exactly as written.

## Threat Model Disposition

- **T-06-03 (mitigate)**: destination passes verbatim as a distinct argv element through the existing `SubprocessRunner.run` array — no shell string composition anywhere.
- **T-06-04 (accept)**: error embeds exit code + full output for diagnosis; no audit surface for a local CLI.

## Self-Check: PASSED

All 6 commits exist on `main`; all 5 modified files exist on disk; all verification commands re-ran green.
