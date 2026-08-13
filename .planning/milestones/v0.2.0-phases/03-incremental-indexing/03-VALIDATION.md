---
phase: 03-incremental-indexing
slug: incremental-indexing
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-12
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`@Suite` / `@Test` / `#expect`) |
| **Config file** | none — built into Swift 6.2 toolchain |
| **Quick run command** | `swift test --filter ContentHasher` (or any single suite) |
| **Full suite command** | `swift test` |
| **Estimated runtime** | ~45 seconds (unit <5s; integration ~20-30s with double-build) |

---

## Sampling Rate

- **After every task commit:** Run `swift test --filter <NewSuiteName>`
- **After every plan wave:** Run `swift test` (full suite)
- **Before `$gsd-verify-work`:** Full suite must be green + cache round-trip verified
- **Max feedback latency:** ~45 seconds (integration tests shell out to swift build)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-01-T1 | 01 | 1 | INCR-03 | — | N/A — pure crypto | unit | `swift test --filter ContentHasher` | ❌ W0 | ⬜ pending |
| 03-01-T2 | 01 | 1 | INCR-06 | — | N/A — data struct | unit | `swift test --filter IndexManifest` | ❌ W0 | ⬜ pending |
| 03-01-T3 | 01 | 1 | INCR-03 | — | N/A — file I/O | unit | `swift test --filter CacheStore` | ❌ W0 | ⬜ pending |
| 03-02-T1 | 02 | 2 | INCR-03, INCR-04, TEST-04 | — | Cache correctness | integration | `swift build && swift test --filter IncrementalIntegration` | ❌ W0 | ⬜ pending |
| 03-02-T2 | 02 | 2 | INCR-01, INCR-02, INCR-05, INCR-06 | — | CLI flag handling | integration | `swift build && swift test --filter IncrementalIntegration` | ❌ W0 | ⬜ pending |
| 03-02-T3 | 02 | 2 | INCR-06, INCR-05, TEST-04 | — | Invalidation correctness | integration | `swift test --filter IncrementalIntegration` | ❌ W0 | ⬜ pending |

---

## Wave 0 Requirements

- [ ] `Tests/scip-swiftTests/ContentHasherTests.swift` — unit tests for SHA256 hashing (INCR-03)
- [ ] `Tests/scip-swiftTests/IndexManifestTests.swift` — unit tests for version invalidation (INCR-06)
- [ ] `Tests/scip-swiftTests/CacheStoreTests.swift` — unit tests for document protobuf I/O (INCR-03)
- [ ] `Tests/scip-swiftTests/IncrementalIntegrationTests.swift` — integration test for cache round-trip (TEST-04)

---

## Manual-Only Verifications

- **Cache persistence across runs:** Run `scip-swift <repo> --cache-dir /tmp/test-cache` twice; verify second run is faster and output is identical
- **Content hash invalidation:** Modify a source file, re-run, verify only that file's document is regenerated
- **Version invalidation:** Change `.swift-version` or bump `Version.swift`, re-run, verify entire cache is invalidated
- **`--index-only` mode:** Run with `--index-only` after a prior build, verify build step is skipped

---

*Created: 2026-08-12 during plan-phase revision loop (plan-checker blocker fix)*
