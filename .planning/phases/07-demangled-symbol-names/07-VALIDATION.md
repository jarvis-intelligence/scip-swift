---
phase: 7
slug: demangled-symbol-names
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-16
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`@Suite`/`@Test`) |
| **Config file** | none — Package.swift test target |
| **Quick run command** | `swift test --filter DemanglerTests` |
| **Full suite command** | `swift test` (CI) / filter+skip partition union under the 300s local ceiling |
| **Estimated runtime** | ~15s quick (pure unit, no xcodebuild) / ~4-6min full partition |

---

## Sampling Rate

- **After every task commit:** `swift test --filter DemanglerTests` (pure unit — dlopen resolution, rewrite, fallback, truncation-retry)
- **After every plan wave:** `swift test --skip Xcode` (all non-xcodebuild suites incl. integration, merge, incremental)
- **Before `$gsd-verify-work`:** full partition union covering all enumerated tests must be green
- **Max feedback latency:** ~120 seconds

---

## Per-Task Verification Map

| Task | Verification | Type | Frequency |
|------|--------------|------|-----------|
| SwiftDemangler module (dlopen resolve, s:→_$s rewrite, caller-owned buffer, truncation retry) | New DemanglerTests: real USRs demangle to expected strings; `c:`/closure/garbage return fallback (symbol.name), never throw; buffer-too-small retry returns full string | unit | every task commit |
| Display-name wiring in SCIPIndexBuilder (display_name field only) | Unit: symbol information carries demangled display_name; canonical `symbol` string byte-identical to pre-phase shape (`swift <usr>`) | unit | every task commit |
| Identity invariants untouched | `swift test --skip Xcode` — formatter tests (11), IncrementalIntegrationTests byte-identity, MultiRepoMerge dedup all green unchanged | unit+integration | every wave |
| Cache invalidation (converter version bump) | IndexManifestTests.converterMismatch still green; manual run pair: old-format cache dir → second run regenerates (not serves) documents | unit + integration (once) | once per wave |
| `--no-demangle` flag threading | Unit: flag parsed; index output matches v0.2.x opaque shape (no demangled display names) | unit + integration | task completion |
| End-to-end index content | IntegrationTests (MiniSwiftPackage): emitted .scip contains demangled display names for Swift symbols and opaque fallback for others | integration | task completion + wave end |

---

## Rationale

The demangler is a pure, deterministic transform — the highest-frequency checks (rewrite, fallback, buffer handling) run as fast unit tests with zero xcodebuild cost. Identity invariants (byte-identity, merge dedup, formatter tests) run at wave boundaries because they are the SYMBOL-03 contract: they must be green WITHOUT modification, proving the canonical symbol string never changed. The only re-baselined surface is IntegrationTests.swift:42-45 (document/symbol count expectations if display names alter assertions).
