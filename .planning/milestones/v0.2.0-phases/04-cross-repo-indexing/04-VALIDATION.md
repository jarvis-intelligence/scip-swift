---
phase: 04-cross-repo-indexing
slug: cross-repo-indexing
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-12
---

# Phase 4 — Validation Strategy

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`@Suite` / `@Test`) |
| **Quick run command** | `swift test --filter ScipIndexMerger` |
| **Full suite command** | `swift test` |
| **Estimated runtime** | ~60 seconds (multi-repo integration builds 2 fixtures) |

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | Status |
|---------|------|------|-------------|-----------|-------------------|--------|
| 04-01-T1 | 01 | 1 | CROSS-01,02,03 | integration | `swift build && swift test --filter IndexMany` | ⬜ pending |
| 04-01-T2 | 01 | 1 | CROSS-01,02,03 | unit | `swift test --filter ScipIndexMerger` | ⬜ pending |
| 04-02-T1 | 02 | 2 | CROSS-04,05 | unit | `swift test --filter ScipIndexMerger` | ⬜ pending |
| 04-02-T2 | 02 | 2 | CROSS-04,05,TEST-05 | integration | `swift test --filter MultiRepoMerge` | ⬜ pending |

---

*Created: 2026-08-12*
