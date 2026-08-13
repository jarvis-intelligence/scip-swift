---
phase: 02-homebrew-distribution-release-pipeline
slug: homebrew-distribution-release-pipeline
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-12
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`@Suite` / `@Test` / `#expect`) + GitHub Actions |
| **Config file** | none — built into Swift 6.2 toolchain |
| **Quick run command** | `swift test --filter DylibCheck` |
| **Full suite command** | `swift test` |
| **Estimated runtime** | ~30 seconds (unit tests <5s; integration ~15-25s) |

---

## Sampling Rate

- **After every task commit:** Run `swift test` (quick — Phase 2 adds only 1 new unit test file)
- **After every plan wave:** Run `swift test` (full suite)
- **Before `$gsd-verify-work`:** Full suite must be green + `release.yml` dry-run check
- **Max feedback latency:** ~30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 02-01-T1 | 01 | 1 | DIST-04 | — | Dylib path validated before load | unit | `swift test --filter DylibCheck` | ❌ W0 | ⬜ pending |
| 02-02-T1 | 02 | 1 | DIST-01 | — | N/A — checkpoint decision | manual | User confirms tap owner | N/A | ⬜ pending |
| 02-02-T2 | 02 | 1 | DIST-01 | — | Formula downloads verified binary | manual | `brew audit Formula/scip-swift.rb` | ❌ W0 | ⬜ pending |
| 02-02-T3 | 02 | 1 | DIST-02, DIST-03 | — | Release CI produces universal binary | manual | `act -W .github/workflows/release.yml` (dry-run) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Tests/scip-swiftTests/DylibCheckTests.swift` — unit test for REQ-DIST-04

*Framework already installed — Swift Testing is part of the toolchain.*

---

## Manual-Only Verifications

- **Homebrew formula correctness**: After creating the tap repo, run `brew install <tap>/scip-swift` on both Apple Silicon and Intel Macs to verify the formula works
- **Universal binary**: After release CI produces the binary, verify `lipo -info` shows both architectures and the binary runs on both
- **Release workflow dry-run**: Use `act` or manually trigger the workflow on a test tag to verify the CI pipeline before the first real release
- **Dylib error message**: Temporarily rename `libIndexStore.dylib` and run `scip-swift` to verify the error message is actionable

---

*Created: 2026-08-12 during plan-phase revision loop (issue fix from plan-checker)*
