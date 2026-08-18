---
phase: 6
slug: xcode-backend-repair-destination-selection
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-08-15
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`@Suite`/`@Test`) |
| **Config file** | none — Package.swift test target |
| **Quick run command** | `swift test --filter XcodebuildBuildRunnerTests` |
| **Full suite command** | `swift test` |
| **Estimated runtime** | ~20s quick (pure unit) / ~3-5min full (includes real-build integration suites) |

---

## Sampling Rate

- **After every task commit:** Run `swift test --filter XcodebuildBuildRunnerTests`
- **After every plan wave:** Run `swift test --filter "Xcode"` (runner + integration suites)
- **Before `$gsd-verify-work`:** Full `swift test` must be green
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

| Task | Verification | Type | Frequency |
|------|--------------|------|-----------|
| Restore `.xcodebuild` dispatch branch | `XcodeIntegrationTests` real xcodebuild run against `Fixtures/XcodeTestProject` produces a `.scip` | integration | once at task completion + every wave end |
| Dispatch helper extraction | `swift build` compiles; `IndexManyCommand` call sites unchanged | build + unit | every task commit |
| `--destination` flag on `XcodebuildBuildRunner` | `XcodebuildBuildRunnerTests` asserts `arguments` contains `["-destination", spec]` when set, and byte-identical arg list when nil (existing 7 tests = regression guard) | unit (pure property) | every task commit |
| `--destination` CLI option threading | Unit test: `IndexCommand` parses `--destination` into runner construction (or integration test passes spec through) | unit | every task commit |
| `xcodebuildDestinationFailed` error case | Unit test: error description contains `-showdestinations` hint and full output marker `Unable to find a device matching the provided destination specifier:` | unit | every task commit |
| Bogus-destination failure path | Integration test: bogus destination exits non-zero with the hint (live-run, ~60s) | integration | once per wave |

---

## Rationale

Pure-property design (`XcodebuildBuildRunner.arguments`) keeps the highest-frequency checks (flag threading, arg construction) as fast unit assertions — no xcodebuild spawn. Real xcodebuild runs (fixture build, bogus-destination failure) are sampled only at task completion and wave boundaries because each costs ~60s. The nil-destination arg-list identity test guards REPAIR-02's "omitting the flag preserves current behavior" clause at unit frequency.
