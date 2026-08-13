---
phase: 01-symbol-metadata-enrichment
slug: symbol-metadata-enrichment
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-11
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`@Suite` / `@Test` / `#expect` / `#require`) |
| **Config file** | none — built into Swift 6.2 toolchain |
| **Quick run command** | `swift test --filter SymbolRoleMapping` (or any single suite) |
| **Full suite command** | `swift test` |
| **Estimated runtime** | ~30 seconds (unit tests <5s each; integration ~15-25s) |

---

## Sampling Rate

- **After every task commit:** Run `swift test --filter <MapperName>` for the mapper being modified
- **After every plan wave:** Run `swift test` (full suite)
- **Before `$gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~30 seconds (unit), ~60 seconds (integration)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-01-T1 | 01 | 1 | META-06 | T-01-01 | N/A — compiler data | integration | `swift test --filter RelationSpike` | ✅ W0 | ⬜ pending |
| 01-01-T2 | 01 | 1 | META-01, TEST-02 | T-01-02 | N/A — pure function | unit | `swift test --filter RelationshipMapping` | ❌ W0 | ⬜ pending |
| 01-01-T3 | 01 | 1 | META-01 | T-01-02 | N/A — additive wiring | integration | `swift build && swift test --filter RelationSpike` | ❌ W0 | ⬜ pending |
| 01-02-T1 | 02 | 2 | META-03, TEST-03 | T-02-01 | N/A — pure function | unit | `swift test --filter SymbolRoleMapping` | ✅ exists | ⬜ pending |
| 01-02-T2 | 02 | 2 | META-03 | T-02-01 | N/A — call site update | integration | `swift build && swift test --filter Integration` | ❌ W0 | ⬜ pending |
| 01-02-T3 | 02 | 2 | META-02 | T-02-02 | N/A — additive | integration | `swift build && swift test --filter Integration` | ❌ W0 | ⬜ pending |
| 01-03-T1 | 03 | 2 | META-05 | T-03-01 | N/A — pure function | unit | `swift test --filter SignatureMapping` | ❌ W0 | ⬜ pending |
| 01-03-T2 | 03 | 2 | META-04 | T-03-01 | N/A — classification | integration | `swift build && swift test --filter Integration` | ❌ W0 | ⬜ pending |
| 01-03-T3 | 03 | 2 | META-04, META-05 | T-03-02 | N/A — wiring | integration | `swift build && swift test --filter Integration` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Tests/scip-swiftTests/RelationshipMappingTests.swift` — unit tests for REQ-META-01
- [ ] `Tests/scip-swiftTests/SignatureMappingTests.swift` — unit tests for REQ-META-05
- [ ] `Tests/scip-swiftTests/RelationSpikeTests.swift` — integration test for REQ-META-06
- [ ] Existing `Tests/scip-swiftTests/SymbolRoleMappingTests.swift` — extended for REQ-META-03

*Framework already installed — Swift Testing is part of the toolchain.*

---

## Manual-Only Verifications

- **scip lint on output**: After Wave 2, run `scip lint` on the `.scip` output from both `MiniSwiftPackage` and `RelationSpikeFixture` fixtures. Verify no `missingRelationshipFlagError`, `missingSymbolInRelationshipError`, `bothLocalAndExternalSymbolError`, or `forwardDefIsDefinitionError`.
- **Relationship boolean correctness**: Manually inspect at least one `Scip_Relationship` in the output to verify `is_implementation` is true for class inheritance and `is_reference` is true for method overrides.

---

*Created: 2026-08-11 during plan-phase revision loop (issue fix from plan-checker)*
