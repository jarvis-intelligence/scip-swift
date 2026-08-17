---
phase: 8
slug: exact-occurrence-ranges
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-17
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`@Suite`/`@Test`) |
| **Config file** | none — Package.swift test target (now depends on swift-syntax 602.0.0) |
| **Quick run command** | `swift test --filter SwiftSyntaxRefinerTests` |
| **Full suite command** | `swift test` (CI) / `--skip Xcode` + `--filter Xcode` partition union under the 300s local ceiling |
| **Estimated runtime** | ~20s quick / ~5-8min full partition (cold release builds +26-60s once swift-syntax lands in the dependency graph) |

---

## Sampling Rate

- **After every task commit:** `swift test --filter SwiftSyntaxRefinerTests` (pure unit — token map, line table, exact-extent math incl. Unicode fixture)
- **After every plan wave:** `swift test --skip Xcode` (all non-xcodebuild suites; existing PositionMappingTests must stay green unchanged)
- **Before `$gsd-verify-work`:** full partition union green (125 pre-phase tests + new)
- **Max feedback latency:** ~150 seconds

---

## Per-Task Verification Map

| Task | Verification | Type | Frequency |
|------|--------------|------|-----------|
| Package.swift swift-syntax 602.0.0 dependency | `swift build` resolves and compiles; `swift package resolve` pins 602.0.0 | build | task commit |
| Line-start byte table + (line, col) ↔ offset conversion | Unit: known offsets map to expected (line, utf8Column) and back; 1-based↔0-based conversions; multi-byte lines | unit | every task commit |
| Token extent map (start anchor → exact end) | Unit: identifiers/compound names/multi-byte-prefixed lines produce exact ends (`positionAfterSkippingLeadingTrivia.utf8Offset + text.utf8.count` — NOT endPosition); trailing-trivia regression case | unit | every task commit |
| Error-node fallback (RANGE-03) | Unit: fixture with syntax errors still yields tokens for valid regions; occurrences anchored in error regions return nil → name-length fallback | unit | every task commit |
| Builder wiring (lookup per occurrence, fallback on nil) | Unit: occurrence with anchor hit emits exact end; anchor miss emits current approximation; --cache-dir docs serve cached (already-exact) ranges | unit | task commit |
| Unicode end-to-end (RANGE-02) | Integration: fixture with emoji/CJK earlier on the line asserts hand-computed expected columns in the emitted .scip | integration | task completion + wave end |
| Compound-name drift eliminated (RANGE-01) | Integration: `greet(name:)` / `getter:`/`setter:` occurrences assert exact ends (display-name length would drift +7..+13 bytes) | integration | task completion |
| Existing suites unbroken | `swift test --skip Xcode` green with PositionMappingTests unchanged (approximation still used as fallback) | unit+integration | every wave |

---

## Rationale

The refiner is deterministic pure logic — the highest-frequency gates (conversion math, extent map, fallback) run as fast unit tests against in-memory source strings, including the researcher's hand-computed Unicode expectations. Integration runs (real fixture builds ~30-90s) are rate-limited to task completion and wave boundaries. PositionMappingTests stay untouched — the approximation remains the documented fallback path, so the phase's correctness contract is additive (exact when the token map hits, approximate when it doesn't).
