---
phase: 9
slug: symbol-documentation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-17
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`@Suite`/`@Test`) |
| **Config file** | none — Package.swift test target (swift-syntax 602.0.0 already pinned) |
| **Quick run command** | `swift test --filter SwiftSyntaxRefinerTests` |
| **Full suite command** | `swift test` (CI) / `--skip Xcode` + `--filter Xcode` + DylibCheck partition union under the 300s ceiling |
| **Estimated runtime** | ~20s quick / ~5-8min full partition |

---

## Sampling Rate

- **After every task commit:** `swift test --filter SwiftSyntaxRefinerTests` (doc-map corpus, normalization, exclusions, parse-count hook)
- **After every plan wave:** `swift test --skip Xcode` — NOTE: this name filter also skips DylibCheckTests; add `--filter DylibCheckTests` to the wave gate union (the Phase 8 verifier's count-correction lesson)
- **Before `$gsd-verify-work`:** full partition union green (139 pre-phase + new)
- **Max feedback latency:** ~150 seconds

---

## Per-Task Verification Map

| Task | Verification | Type | Frequency |
|------|--------------|------|-----------|
| Doc map in SwiftSyntaxRefiner (name-token keyed, same parse) | Unit: documented decls (class/struct/func/var/enum/protocol/extension/typealias/init/deinit/case) map anchor→doc; attributed decls (`@inline(__always) func`) hit via NAME-token key not first-token; `////` dropped | unit | every task commit |
| Markdown normalization | Unit: `///` + one space stripped; `/** */` wrappers stripped with per-line `*`; multi-line joins with \n; empty `///` = blank paragraph line | unit | every task commit |
| Exclusions (DOCS-02) | Unit: `//` noise, license headers, trailing comments after statements, comments on non-declaration tokens → absent from map | unit | every task commit |
| One-parse contract (DOCS-03) | Unit + integration: package-visible parse-count hook asserts exactly 1 parse per file per run (before/after doc extraction) | unit + integration | every task commit |
| Builder wiring (documentation field) | Unit: symbol info for documented decl carries doc lines; undocumented stays empty; getter/setter USRs inherit property doc (asserted, by design) | unit | task commit |
| End-to-end (DOCS-01) | Integration: Fixtures/DocumentationFixture builds real SwiftPM; emitted .scip contains Markdown docs on corresponding symbols; scip lint clean | integration | task completion + wave end |
| Cache round-trip | Integration: --cache-dir run pair; cached docs carry documentation identical to fresh | integration | once per wave |

---

## Rationale

Doc extraction is pure trivia-walking logic on the already-parsed tree — the highest-frequency gates (normalization, exclusions, name-token keying) run as fast unit tests over in-memory source strings. The parse-count hook makes DOCS-03 mechanically assertable rather than by-inspection. Integration runs (real DocumentationFixture build) are rate-limited to task completion and wave boundaries. No existing test asserts documentation emptiness — the re-baseline surface is zero, verified in research.
